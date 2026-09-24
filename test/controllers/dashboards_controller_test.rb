require 'test_helper'

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Dash User', email: 'dashboards_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Dash Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Dash Team', identifier: 'DSC')
    @team.team_memberships.create!(user: @user)

    @other_user = User.create!(name: 'Other', email: 'dashboards_other@example.com', password: 'password')
    @other_dashboard = @other_user.dashboards.create!(name: 'Not yours')

    # A team the signed-in user is not a member of; its issues must never render.
    @other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'DSX')
    @other_team.team_memberships.create!(user: @other_user)

    @today = Time.current.in_time_zone(@user.time_zone).to_date

    sign_in_as(@user)
  end

  test 'index redirects to the first dashboard by position' do
    @user.dashboards.create!(name: 'Second', position: 2)
    first = @user.dashboards.create!(name: 'First', position: 1)

    get dashboards_path

    assert_redirected_to dashboard_path(first)
  end

  test 'index renders the empty state when the user has no dashboards' do
    get dashboards_path

    assert_response :success
    assert_includes response.body, 'No dashboards yet'
  end

  test 'show highlights the dashboard in the sidebar' do
    dashboard = @user.dashboards.create!(name: 'Today')

    get dashboard_path(dashboard)

    assert_response :success
    assert_select "a.bg-foreground[href='#{dashboard_path(dashboard)}']"
  end

  test 'show with no groups renders a placeholder' do
    dashboard = @user.dashboards.create!(name: 'Today')

    get dashboard_path(dashboard)

    assert_includes response.body, 'No groups yet'
  end

  # --- show: filters ---------------------------------------------------------

  test 'default filter renders due-today and overdue issues but not future ones' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    create_issue(title: 'Due today issue', due_date: @today)
    create_issue(title: 'Overdue issue', due_date: @today - 3)
    create_issue(title: 'Future issue', due_date: @today + 2)

    get dashboard_path(dashboard)

    assert_response :success
    assert_includes response.body, 'Due today issue'
    assert_includes response.body, 'Overdue issue'
    assert_not_includes response.body, 'Future issue'
    assert_select 'span.text-red-400', text: 'Overdue · 3d'
  end

  test 'overdue rows sort before due-today rows' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    create_issue(title: 'Due today issue', due_date: @today)
    create_issue(title: 'Overdue issue', due_date: @today - 1)

    get dashboard_path(dashboard)

    assert_operator response.body.index('Overdue issue'), :<, response.body.index('Due today issue')
  end

  test 'filter=hot includes an urgent issue with no due date' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    create_issue(title: 'Urgent undated', priority: :urgent)
    create_issue(title: 'Low undated', priority: :low)

    get dashboard_path(dashboard)
    assert_not_includes response.body, 'Urgent undated'

    get dashboard_path(dashboard, filter: 'hot')
    assert_includes response.body, 'Urgent undated'
    assert_not_includes response.body, 'Low undated'
  end

  test 'mine=1 leaves out issues assigned to other people' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    create_issue(title: 'My issue', due_date: @today, assignee: @user)
    create_issue(title: 'Their issue', due_date: @today, assignee: @other_user)
    create_issue(title: 'Unassigned issue', due_date: @today)

    get dashboard_path(dashboard, mine: 1)

    assert_includes response.body, 'My issue'
    assert_not_includes response.body, 'Their issue'
    assert_not_includes response.body, 'Unassigned issue'
  end

  test 'filter and mine combine' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    create_issue(title: 'My urgent', priority: :urgent, assignee: @user)
    create_issue(title: 'Their urgent', priority: :urgent, assignee: @other_user)
    create_issue(title: 'My low', priority: :low, assignee: @user)

    get dashboard_path(dashboard, filter: 'hot', mine: 1)

    assert_includes response.body, 'My urgent'
    assert_not_includes response.body, 'Their urgent'
    assert_not_includes response.body, 'My low'
  end

  test 'the active tab is highlighted and tabs keep the mine param' do
    dashboard = @user.dashboards.create!(name: 'Today')

    get dashboard_path(dashboard, filter: 'week', mine: 1)

    assert_select 'a[role=tab][aria-selected=true].bg-foreground', text: 'This week'
    assert_select "a[role=tab][href='#{dashboard_path(dashboard, filter: 'hot', mine: 1)}']", text: 'Urgent / High'
    assert_select "a[role=tab][href='#{dashboard_path(dashboard, mine: 1)}']", text: 'Due today'
    assert_select "a[aria-pressed=true][href='#{dashboard_path(dashboard, filter: 'week')}']", text: /Mine only/
  end

  # --- show: counts, access, rows --------------------------------------------

  test 'header pills show dashboard-wide counts that ignore the active tab' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    group_with(dashboard, @team) # same source twice: counts must not double
    create_issue(due_date: @today)
    create_issue(due_date: @today)
    create_issue(due_date: @today - 5)
    create_issue(due_date: @today + 5)

    get dashboard_path(dashboard)
    assert_select '[data-testid=dashboard-counts]', text: /2 due today/
    assert_select '[data-testid=dashboard-counts]', text: /1 overdue/

    get dashboard_path(dashboard, filter: 'hot')
    assert_select '[data-testid=dashboard-counts]', text: /2 due today/
    assert_select '[data-testid=dashboard-counts]', text: /1 overdue/
  end

  test "issues from a team the user isn't in are not rendered" do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @other_team)
    create_issue(team: @other_team, title: 'Secret issue', due_date: @today)

    get dashboard_path(dashboard)

    assert_response :success
    assert_not_includes response.body, 'Secret issue'
    assert_includes response.body, 'Nothing due today'
  end

  test 'rows link to the issue on its own team' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    project = @team.projects.create!(name: 'Dash Project')
    issue = create_issue(title: 'Linked issue', due_date: @today, project: project, assignee: @user)

    get dashboard_path(dashboard)

    assert_select "a[href='#{team_issue_path(@team, issue)}']", minimum: 1
    assert_includes response.body, 'Dash Project'
    assert_includes response.body, issue.identifier
  end

  test 'an empty group shows a filter-specific message' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)

    get dashboard_path(dashboard, filter: 'open')

    assert_includes response.body, 'Nothing open'
  end

  test 'sidebar shows only the Dashboards header when the user has none' do
    get dashboards_path

    assert_response :success
    assert_includes response.body, 'Dashboards'
    assert_select "a[href^='/dashboards/']", count: 0
  end

  test 'create appends a dashboard and redirects to it' do
    @user.dashboards.create!(name: 'Existing', position: 3)

    assert_difference -> { @user.dashboards.count }, 1 do
      post dashboards_path, params: { dashboard: { name: 'Today', description: 'Focus' } }
    end

    created = @user.dashboards.order(:id).last
    assert_redirected_to dashboard_path(created)
    assert_equal 'Today', created.name
    assert_equal 'Focus', created.description
    assert_equal 4, created.position
  end

  test 'create with a blank name responds 422' do
    assert_no_difference -> { Dashboard.count } do
      post dashboards_path, params: { dashboard: { name: '' } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, 'Name can&#39;t be blank'
  end

  test 'update renames the dashboard' do
    dashboard = @user.dashboards.create!(name: 'Today')

    patch dashboard_path(dashboard), params: { dashboard: { name: 'This week', description: 'Seven days out' } }

    assert_redirected_to dashboard_path(dashboard)
    dashboard.reload
    assert_equal 'This week', dashboard.name
    assert_equal 'Seven days out', dashboard.description
  end

  test 'update with a blank name responds 422 and keeps the old name' do
    dashboard = @user.dashboards.create!(name: 'Today')

    patch dashboard_path(dashboard), params: { dashboard: { name: '' } }

    assert_response :unprocessable_entity
    assert_equal 'Today', dashboard.reload.name
  end

  test 'destroy redirects to the next dashboard' do
    first = @user.dashboards.create!(name: 'First', position: 1)
    second = @user.dashboards.create!(name: 'Second', position: 2)

    assert_difference -> { @user.dashboards.count }, -1 do
      delete dashboard_path(first)
    end

    assert_redirected_to dashboards_path
    follow_redirect!
    assert_redirected_to dashboard_path(second)
  end

  test 'destroying the last dashboard lands on the empty state' do
    only = @user.dashboards.create!(name: 'Only')

    delete dashboard_path(only)
    follow_redirect!

    assert_response :success
    assert_includes response.body, 'No dashboards yet'
    assert_includes response.body, 'Dashboard deleted'
  end

  test "another user's dashboard is not found on show, update and destroy" do
    get dashboard_path(@other_dashboard)
    assert_response :not_found

    patch dashboard_path(@other_dashboard), params: { dashboard: { name: 'Hijacked' } }
    assert_response :not_found
    assert_equal 'Not yours', @other_dashboard.reload.name

    delete dashboard_path(@other_dashboard)
    assert_response :not_found
    assert Dashboard.exists?(@other_dashboard.id)
  end

  test 'requires authentication' do
    sign_out

    get dashboards_path

    assert_redirected_to new_session_path
  end

  private

  def group_with(dashboard, *sources)
    dashboard.groups.create!(name: "Group #{dashboard.groups.count + 1}").tap do |group|
      sources.each { |source| group.sources.create!(source: source) }
    end
  end

  def create_issue(team: @team, title: "Issue #{SecureRandom.hex(3)}", **attrs)
    team.issues.create!(title: title, lane: team.lanes.first, creator: @user, **attrs)
  end
end
