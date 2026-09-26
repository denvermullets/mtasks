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

  test 'a group with no sources is still returned with an empty issue list and is not inaccessible' do
    group = @dashboard.groups.create!(name: 'Empty')

    assert_equal [{ group: group, issues: [], inaccessible: false }], query.groups
  end

  # --- inaccessible --------------------------------------------------------

  test 'a group whose sources are all on teams the user is not in is inaccessible' do
    group = group_with(@other_team, @other_project)

    assert entry_for(query, group)[:inaccessible]
  end

  test 'a group whose only team was archived is inaccessible' do
    group = group_with(@team_a, @project_a)
    @team_a.update!(archived_at: Time.current)

    assert entry_for(query, group)[:inaccessible]
  end

  test 'a group with at least one accessible source is not inaccessible' do
    group = group_with(@other_team, @project_a)

    assert_not entry_for(query, group)[:inaccessible]
  end

  # --- include_all ---------------------------------------------------------

  test 'a source without include_all only contributes issues assigned to the user' do
    group = group_with(@team_a, @project_b, include_all: false)
    mine_in_team = create_issue(@team_a, due_date: TODAY, assignee: @user)
    mine_in_project = create_issue(@team_b, project: @project_b, due_date: TODAY, assignee: @user)
    create_issue(@team_a, due_date: TODAY, assignee: @other_user)
    create_issue(@team_a, due_date: TODAY)
    create_issue(@team_b, project: @project_b, due_date: TODAY)

    result = query
    assert_equal [mine_in_team, mine_in_project], issues_for(result, group)
    assert_equal 2, result.due_today_count
  end

  test 'include_all is per source' do
    group = @dashboard.groups.create!(name: 'Mixed')
    group.sources.create!(source: @team_a, include_all: true)
    group.sources.create!(source: @team_b)
    theirs_in_a = create_issue(@team_a, due_date: TODAY, assignee: @other_user)
    mine_in_b = create_issue(@team_b, due_date: TODAY, assignee: @user)
    create_issue(@team_b, due_date: TODAY, assignee: @other_user)

    assert_equal [theirs_in_a, mine_in_b].sort_by(&:id), issues_for(query, group).sort_by(&:id)
  end

  test 'counts include every issue from a source that any group marks include_all' do
    group_with(@team_a, include_all: false)
    group_with(@team_a)
    create_issue(@team_a, due_date: TODAY, assignee: @other_user)

    assert_equal 1, query.due_today_count
  end

  test 'mine still narrows include_all sources' do
    group = group_with(@team_a)
    mine = create_issue(@team_a, due_date: TODAY, assignee: @user)
    create_issue(@team_a, due_date: TODAY, assignee: @other_user)

    assert_equal [mine], issues_for(query(mine: true), group)
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

  test 'an issue without a due date inherits its project due date' do
    group = group_with(@team_a)
    @project_a.update!(due_date: TODAY + 3)
    inherited = create_issue(@team_a, project: @project_a, due_date: nil)
    own_date_wins = create_issue(@team_a, project: @project_a, due_date: TODAY + 10)
    create_issue(@team_a, due_date: nil)

    assert_equal [inherited], issues_for(query(filter: 'week'), group)
    assert_empty issues_for(query, group)
    assert_equal [inherited, own_date_wins], issues_for(query(filter: 'open'), group).first(2)
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

  # --- search --------------------------------------------------------------

  test 'search narrows every group by title and leaves non-matching groups empty' do
    group_a = group_with(@team_a)
    group_b = group_with(@team_b)
    sso = create_issue(@team_a, title: 'Investigate SSO login issue', due_date: TODAY)
    create_issue(@team_a, title: 'Prepare launch comms', due_date: TODAY)
    create_issue(@team_b, title: 'Upgrade database', due_date: TODAY)

    result = query(search: 'sso')
    assert_equal 'sso', result.search
    assert_equal [sso], issues_for(result, group_a)
    assert_equal [], issues_for(result, group_b)
  end

  test 'search finds an issue by identifier' do
    group = group_with(@team_a)
    issue = create_issue(@team_a, title: 'Needle', due_date: TODAY)
    create_issue(@team_a, title: 'Hay', due_date: TODAY)

    assert_equal [issue], issues_for(query(search: "DQA-#{issue.team_number}"), group)
    assert_equal [issue], issues_for(query(search: "dqa-#{issue.team_number}"), group)
    assert_equal [], issues_for(query(search: "DQB-#{issue.team_number}"), group)
  end

  test 'blank search returns everything' do
    group = group_with(@team_a)
    create_issue(@team_a, due_date: TODAY)
    create_issue(@team_a, due_date: TODAY)

    assert_equal 2, issues_for(query(search: '   '), group).size
    assert_equal '', query(search: nil).search
  end

  test 'search does not change the header counts' do
    group_with(@team_a)
    create_issue(@team_a, title: 'SSO', due_date: TODAY)
    create_issue(@team_a, title: 'Other', due_date: TODAY - 1)

    result = query(search: 'sso')
    assert_equal 1, result.due_today_count
    assert_equal 1, result.overdue_count
  end

  # --- team filter ---------------------------------------------------------

  test 'team_id limits every group and the counts to that team' do
    group = group_with(@team_a, @team_b)
    in_a = create_issue(@team_a, due_date: TODAY)
    create_issue(@team_b, due_date: TODAY)
    create_issue(@team_b, due_date: TODAY - 1)

    result = query(team_id: @team_a.id)
    assert_equal @team_a.id, result.team_id
    assert_equal [in_a], issues_for(result, group)
    assert_equal 1, result.due_today_count
    assert_equal 0, result.overdue_count
  end

  test 'team_id accepts the string form a URL param arrives in' do
    group = group_with(@team_a, @team_b)
    in_a = create_issue(@team_a, due_date: TODAY)
    create_issue(@team_b, due_date: TODAY)

    assert_equal [in_a], issues_for(query(team_id: @team_a.id.to_s), group)
  end

  test 'team_id narrows a group whose source is a project on that team' do
    group = group_with(@project_a, @project_b)
    in_a = create_issue(@team_a, project: @project_a, due_date: TODAY)
    create_issue(@team_b, project: @project_b, due_date: TODAY)

    assert_equal [in_a], issues_for(query(team_id: @team_a.id), group)
  end

  test 'a team id the user cannot access is ignored and leaks nothing' do
    group = group_with(@team_a, @other_team)
    mine = create_issue(@team_a, due_date: TODAY)
    create_issue(@other_team, due_date: TODAY)

    [@other_team.id, 'abc', '', nil, 0].each do |forged|
      result = query(team_id: forged)
      assert_nil result.team_id, "team_id #{forged.inspect} should be dropped"
      assert_equal [mine], issues_for(result, group)
      assert_equal 1, result.due_today_count
    end
  end

  test 'team_ids lists the accessible teams behind the sources, including project owners' do
    group_with(@team_a)
    group_with(@project_b)
    group_with(@other_team, @other_project)

    assert_equal [@team_a.id, @team_b.id], query.team_ids.sort
    assert_equal [], DashboardIssuesQuery.call(user: @user, dashboard: @user.dashboards.create!(name: 'Empty')).team_ids
  end

  test 'search, team, filter and mine combine' do
    group = group_with(@team_a, @team_b)
    match = create_issue(@team_a, title: 'SSO urgent mine', priority: :urgent, assignee: @user)
    create_issue(@team_a, title: 'SSO urgent theirs', priority: :urgent, assignee: @other_user)
    create_issue(@team_a, title: 'SSO low mine', priority: :low, assignee: @user)
    create_issue(@team_a, title: 'Other urgent mine', priority: :urgent, assignee: @user)
    create_issue(@team_b, title: 'SSO urgent mine on B', priority: :urgent, assignee: @user)

    result = query(search: 'sso', team_id: @team_a.id, filter: 'hot', mine: true)
    assert_equal [match], issues_for(result, group)
  end

  # --- groups --------------------------------------------------------------

  test 'returns groups in position order' do
    second = @dashboard.groups.create!(name: 'Second', position: 2)
    first = @dashboard.groups.create!(name: 'First', position: 1)

    assert_equal([first, second], query.groups.map { |entry| entry[:group] })
  end

  test 'counts use the project due date when the issue has none' do
    group_with(@team_a)
    @project_a.update!(due_date: TODAY)
    create_issue(@team_a, project: @project_a, due_date: nil)
    create_issue(@team_a, project: @project_a, due_date: TODAY - 2)

    result = query
    assert_equal 1, result.due_today_count
    assert_equal 1, result.overdue_count
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

  # Sources show every issue by default here; the assigned-to-me default has its own tests.
  def group_with(*sources, include_all: true)
    @dashboard.groups.create!(name: "Group #{@dashboard.groups.count + 1}").tap do |group|
      sources.each { |source| group.sources.create!(source: source, include_all: include_all) }
    end
  end

  def issues_for(result, group)
    entry_for(result, group).fetch(:issues)
  end

  def entry_for(result, group)
    result.groups.find { |entry| entry[:group] == group }
  end

  def create_issue(team, **attrs)
    team.issues.create!(title: "Issue #{SecureRandom.hex(3)}", lane: team.lanes.first, creator: @user, **attrs)
  end
end
