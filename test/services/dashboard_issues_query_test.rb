require 'test_helper'

class DashboardIssuesQueryTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 24)

  setup do
    @user = User.create!(name: 'Dash User', email: 'dashboard_query@example.com', password: 'password')
    @other_user = User.create!(name: 'Other User', email: 'dashboard_query_other@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Dash Workspace', owner: @user)

    @team_a = @workspace.teams.create!(name: 'Team A', identifier: 'DQA')
    @team_b = @workspace.teams.create!(name: 'Team B', identifier: 'DQB')
    @other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'DQX')
    @team_a.team_memberships.create!(user: @user)
    @team_b.team_memberships.create!(user: @user)
    @other_team.team_memberships.create!(user: @other_user)

    @project_a = @team_a.projects.create!(name: 'Project A')
    @project_b = @team_b.projects.create!(name: 'Project B')
    @other_project = @other_team.projects.create!(name: 'Other Project')

    @dashboard = @user.dashboards.create!(name: 'Today')
  end

  # --- sources -------------------------------------------------------------

  test 'an issue whose team is a source appears' do
    group = group_with(@team_a)
    issue = create_issue(@team_a, due_date: TODAY)

    result = query
    assert_equal [issue], issues_for(result, group)
  end

  test 'an issue whose project is a source appears even when its team is not a source' do
    group = group_with(@project_b)
    in_project = create_issue(@team_b, project: @project_b, due_date: TODAY)
    create_issue(@team_b, due_date: TODAY)

    assert_equal [in_project], issues_for(query, group)
  end

  test 'archived, completed and canceled issues never appear' do
    group = group_with(@team_a)
    now = Time.current
    create_issue(@team_a, due_date: TODAY, archived_at: now)
    create_issue(@team_a, due_date: TODAY, completed_at: now)
    create_issue(@team_a, due_date: TODAY, canceled_at: now)
    open_issue = create_issue(@team_a, due_date: TODAY)

    assert_equal [open_issue], issues_for(query, group)
    assert_equal [open_issue], issues_for(query(filter: 'open'), group)
  end

  test 'issues from a team the user is not a member of never appear' do
    group = group_with(@other_team, @other_project)
    create_issue(@other_team, due_date: TODAY)
    create_issue(@other_team, project: @other_project, due_date: TODAY)

    result = query
    assert_equal([group], result.groups.map { |entry| entry[:group] })
    assert_equal [], issues_for(result, group)
    assert_equal 0, result.due_today_count
  end

  test 'issues from an archived team never appear' do
    group = group_with(@team_a, @project_a)
    create_issue(@team_a, project: @project_a, due_date: TODAY)
    @team_a.update!(archived_at: Time.current)

    result = query
    assert_equal [], issues_for(result, group)
    assert_equal 0, result.due_today_count
  end

  test 'a group with no accessible sources is still returned with an empty issue list' do
    group = @dashboard.groups.create!(name: 'Empty')

    assert_equal [{ group: group, issues: [] }], query.groups
  end

  # --- mine ----------------------------------------------------------------

  test 'mine limits results to issues assigned to the user' do
    group = group_with(@team_a)
    mine = create_issue(@team_a, due_date: TODAY, assignee: @user)
    create_issue(@team_a, due_date: TODAY, assignee: @other_user)
    create_issue(@team_a, due_date: TODAY)

    assert_equal [mine], issues_for(query(mine: true), group)
    assert_equal [mine], issues_for(query(mine: '1'), group)
    assert_equal 3, issues_for(query(mine: false), group).size
  end

  # --- filters -------------------------------------------------------------

  test 'today filter returns issues due today and overdue only' do
    group = group_with(@team_a)
    overdue = create_issue(@team_a, due_date: TODAY - 1)
    today = create_issue(@team_a, due_date: TODAY)
    create_issue(@team_a, due_date: TODAY + 1)
    create_issue(@team_a, due_date: nil)

    assert_equal [overdue, today], issues_for(query, group)
  end

  test 'week filter returns issues due within the next seven days' do
    group = group_with(@team_a)
    overdue = create_issue(@team_a, due_date: TODAY - 1)
    in_week = create_issue(@team_a, due_date: TODAY + 6)
    create_issue(@team_a, due_date: TODAY + 7)
    create_issue(@team_a, due_date: nil)

    assert_equal [overdue, in_week], issues_for(query(filter: 'week'), group)
  end

  test 'hot filter returns urgent and high priority issues regardless of due date' do
    group = group_with(@team_a)
    urgent = create_issue(@team_a, priority: :urgent, due_date: nil)
    high = create_issue(@team_a, priority: :high, due_date: TODAY + 30)
    create_issue(@team_a, priority: :medium, due_date: TODAY)
    create_issue(@team_a, priority: :low, due_date: TODAY - 1)

    assert_equal [high, urgent], issues_for(query(filter: 'hot'), group)
  end

  test 'open filter returns every unresolved issue' do
    group = group_with(@team_a)
    create_issue(@team_a, due_date: TODAY - 1)
    create_issue(@team_a, due_date: TODAY + 30)
    create_issue(@team_a, due_date: nil)

    assert_equal 3, issues_for(query(filter: 'open'), group).size
  end

  test 'an invalid filter falls back to today' do
    group = group_with(@team_a)
    today = create_issue(@team_a, due_date: TODAY)
    create_issue(@team_a, due_date: TODAY + 1)

    result = query(filter: 'bogus')
    assert_equal 'today', result.filter
    assert_equal [today], issues_for(result, group)
  end

  # --- sorting -------------------------------------------------------------

  test 'sorts by due date with nulls last, then priority, then id' do
    group = group_with(@team_a)
    no_date = create_issue(@team_a, due_date: nil, priority: :urgent)
    later = create_issue(@team_a, due_date: TODAY + 3)
    today_low = create_issue(@team_a, due_date: TODAY, priority: :low)
    today_urgent = create_issue(@team_a, due_date: TODAY, priority: :urgent)
    overdue = create_issue(@team_a, due_date: TODAY - 2)

    assert_equal [overdue, today_urgent, today_low, later, no_date], issues_for(query(filter: 'open'), group)
  end

  # --- today / time zone ---------------------------------------------------

  test 'today follows the user time zone' do
    group = group_with(@team_a)
    @user.update!(settings: { 'time_zone' => 'Pacific Time (US & Canada)' })
    issue = create_issue(@team_a, due_date: Date.new(2026, 9, 23))

    travel_to Time.utc(2026, 9, 24, 3, 0) do
      result = query(today: nil)
      assert_equal Date.new(2026, 9, 23), result.today
      assert_equal 1, result.due_today_count
      assert_equal 0, result.overdue_count
      assert_equal [issue], issues_for(result, group)
    end
  end

  test 'today defaults to UTC when the user has no time zone' do
    travel_to Time.utc(2026, 9, 24, 3, 0) do
      assert_equal Date.new(2026, 9, 24), query(today: nil).today
    end
  end

  # --- header counts -------------------------------------------------------

  test 'counts due today and overdue across the dashboard' do
    group_with(@team_a)
    create_issue(@team_a, due_date: TODAY)
    create_issue(@team_a, due_date: TODAY)
    create_issue(@team_a, due_date: TODAY - 1)
    create_issue(@team_a, due_date: TODAY + 1)
    create_issue(@team_a, due_date: nil)

    result = query
    assert_equal 2, result.due_today_count
    assert_equal 1, result.overdue_count
  end

  test 'counts are deduplicated across groups' do
    team_group = group_with(@team_a)
    project_group = group_with(@project_a)
    issue = create_issue(@team_a, project: @project_a, due_date: TODAY)

    result = query
    assert_equal [issue], issues_for(result, team_group)
    assert_equal [issue], issues_for(result, project_group)
    assert_equal 1, result.due_today_count
  end

  test 'counts ignore the active filter tab' do
    group_with(@team_a)
    create_issue(@team_a, priority: :low, due_date: TODAY - 1)
    create_issue(@team_a, priority: :low, due_date: TODAY)

    result = query(filter: 'hot')
    assert_equal 1, result.due_today_count
    assert_equal 1, result.overdue_count
  end

  test 'counts respect mine' do
    group_with(@team_a)
    create_issue(@team_a, due_date: TODAY, assignee: @user)
    create_issue(@team_a, due_date: TODAY - 1, assignee: @other_user)

    result = query(mine: true)
    assert_equal 1, result.due_today_count
    assert_equal 0, result.overdue_count
  end

  test 'counts exclude teams the user cannot access' do
    group_with(@team_a, @other_team)
    create_issue(@team_a, due_date: TODAY)
    create_issue(@other_team, due_date: TODAY)

    assert_equal 1, query.due_today_count
  end

  # --- groups --------------------------------------------------------------

  test 'returns groups in position order' do
    second = @dashboard.groups.create!(name: 'Second', position: 2)
    first = @dashboard.groups.create!(name: 'First', position: 1)

    assert_equal([first, second], query.groups.map { |entry| entry[:group] })
  end

  test 'a dashboard with no groups returns no groups and zero counts' do
    result = query
    assert_equal [], result.groups
    assert_equal 0, result.due_today_count
    assert_equal 0, result.overdue_count
  end

  private

  def query(today: TODAY, **)
    DashboardIssuesQuery.call(user: @user, dashboard: @dashboard, today: today, **)
  end

  def group_with(*sources)
    @dashboard.groups.create!(name: "Group #{@dashboard.groups.count + 1}").tap do |group|
      sources.each { |source| group.sources.create!(source: source) }
    end
  end

  def issues_for(result, group)
    result.groups.find { |entry| entry[:group] == group }.fetch(:issues)
  end

  def create_issue(team, **attrs)
    team.issues.create!(title: "Issue #{SecureRandom.hex(3)}", lane: team.lanes.first, creator: @user, **attrs)
  end
end
