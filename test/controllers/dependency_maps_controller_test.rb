require 'test_helper'

class DependencyMapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Map User', email: 'dependency_maps@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Map Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Map Team', identifier: 'MAP')
    @team.team_memberships.create!(user: @user)
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @done = @team.lanes.create!(name: 'Done', position: 1)

    sign_in_as(@user)
  end

  test 'renders the chain in upstream, downstream and related sections' do
    a, b, c, d = %w[Alpha Bravo Charlie Delta].map { |title| create_issue(title) }
    link(a, b)
    link(b, c)
    link(b, d, kind: 'relates')

    get team_issue_dependency_map_path(@team, b)

    assert_response :success
    assert_select "#dep_node_#{b.id}[href=?]", team_issue_path(@team, b)
    assert_select "#dep_node_#{a.id}[href=?]", team_issue_dependency_map_path(@team, a)
    assert_select "#dep_node_#{c.id}"
    assert_select "#dep_node_#{d.id}"

    graph = css_select('[data-controller="dependency-map"]').first
    edges = JSON.parse(graph['data-dependency-map-edges-value'])
    assert_equal [[a.id, b.id], [b.id, c.id]], edges.map { |e| [e['from_id'], e['to_id']] }.sort

    # Each list card shows its count next to the heading and one row.
    { 'Blocked by' => a, 'Blocks' => c, 'Related' => d }.each do |heading, issue|
      assert_select 'h3', text: heading do |headings|
        card = headings.first.ancestors('.rounded-xl').first
        assert_includes card.text, issue.title
        assert_equal 1, card.css("a[href='#{team_issue_path(@team, issue)}']").size
      end
    end
  end

  test 'shows the empty state for an issue with no links' do
    issue = create_issue('Loner')

    get team_issue_dependency_map_path(@team, issue)

    assert_response :success
    assert_match 'No dependencies yet.', response.body
    assert_select '[data-controller="dependency-map"]', count: 0
  end

  test "another team's issue is not found" do
    other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
    lane = other_team.lanes.create!(name: 'Backlog', position: 0)
    foreign = other_team.issues.create!(title: 'Foreign', lane: lane, creator: @user)

    get team_issue_dependency_map_path(other_team, foreign)
    assert_response :not_found

    get team_issue_dependency_map_path(@team, foreign)
    assert_response :not_found
  end

  test 'the depth param is clamped between 1 and 5' do
    issues = Array.new(8) { |i| create_issue("Chain #{i}") }
    issues.each_cons(2) { |from, to| link(from, to) }

    get team_issue_dependency_map_path(@team, issues.first, depth: 99)
    assert_select "#dep_node_#{issues[5].id}"
    assert_select "#dep_node_#{issues[6].id}", count: 0
    assert_match 'More beyond depth 5', response.body
    assert_select 'a', text: 'Show more', count: 0

    get team_issue_dependency_map_path(@team, issues.first, depth: 0)
    assert_select "#dep_node_#{issues[1].id}"
    assert_select "#dep_node_#{issues[2].id}", count: 0
    assert_select 'a[href=?]', team_issue_dependency_map_path(@team, issues.first, depth: 2), text: 'Show more'
  end

  test 'a completed upstream issue renders muted' do
    blocker = create_issue('Finished blocker', lane: @done, completed_at: 1.day.ago)
    issue = create_issue('Waiting')
    link(blocker, issue)

    get team_issue_dependency_map_path(@team, issue)

    assert_select "#dep_node_#{blocker.id}.opacity-60", text: /Done/
    assert_select "#dep_node_#{issue.id}.opacity-60", count: 0
  end

  test 'changing the status lands back on the map' do
    issue = create_issue('Moving')
    map_path = team_issue_dependency_map_path(@team, issue)

    patch team_issue_path(@team, issue, format: :html),
          params: { issue: { lane_id: @done.id }, return_to: map_path }

    assert_redirected_to map_path
    assert_equal @done, issue.reload.lane
  end

  test 'query count does not grow with the number of nodes' do
    small = map_query_count(2)
    large = map_query_count(6)

    assert_equal small, large
  end

  private

  # Renders a map whose focus has `fan_out` blockers, blocked issues and related issues, each
  # with a label, and counts the SQL it takes.
  def map_query_count(fan_out)
    label = @team.labels.create!(name: "Label #{fan_out}", color: '#ff0000')
    focus = create_issue("Focus #{fan_out}")
    fan_out.times do |i|
      [[create_issue("Up #{i}"), focus, 'blocks'],
       [focus, create_issue("Down #{i}"), 'blocks'],
       [focus, create_issue("Rel #{i}"), 'relates']].each do |from, to, kind|
        (from == focus ? to : from).labels << label
        link(from, to, kind: kind)
      end
    end

    count_queries { get team_issue_dependency_map_path(@team, focus) }
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  def create_issue(title, lane: @backlog, **attrs)
    @team.issues.create!(title: title, lane: lane, creator: @user, **attrs)
  end

  def link(from, to, kind: 'blocks')
    IssueDependency.create!(blocking_issue: from, blocked_issue: to, kind: kind)
  end
end
