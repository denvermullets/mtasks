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

  test 'index renders the onboarding card when the user has no dashboards' do
    get dashboards_path

    assert_response :success
    assert_select '[data-testid=dashboards-empty]' do
      assert_select 'h2', text: 'Group teams and projects into one view'
      assert_select "button[data-action*='dashboard-form#open'][data-dashboard-form-url-param='#{dashboards_path}']",
                    text: /Create dashboard/
    end
  end

  test 'sidebar offers to create the first dashboard when the user has none' do
    get dashboards_path

    assert_select "button[data-action*='dashboard-form#open'][data-dashboard-form-method-param='post']",
                  text: /Create your first dashboard/
  end

  test 'sidebar drops the first-dashboard link once a dashboard exists' do
    dashboard = @user.dashboards.create!(name: 'Today')

    get dashboard_path(dashboard)

    assert_not_includes response.body, 'Create your first dashboard'
  end

  test 'show highlights the dashboard in the sidebar' do
    dashboard = @user.dashboards.create!(name: 'Today')

    get dashboard_path(dashboard)

    assert_response :success
    assert_select "a.bg-foreground[href='#{dashboard_path(dashboard)}']"
  end

  test 'show with no groups renders the add-group card' do
    dashboard = @user.dashboards.create!(name: 'Today')

    get dashboard_path(dashboard)

    assert_select '[data-testid=dashboard-no-groups]' do
      assert_select 'p', text: 'Add a group to start pulling in issues'
      assert_select 'p', text: /e\.g\. Launch: Web, Mobile and API teams/
      assert_select "button[data-action='click->dashboard-group-form#open']" \
                    "[data-dashboard-group-form-url-param='#{dashboard_groups_path(dashboard)}']" \
                    "[data-dashboard-group-form-method-param='post']",
                    text: /Add group/
    end
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

  # --- show: search and team filter ------------------------------------------

  test 'q narrows the rendered rows but not the header pills' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    second_team = member_team('Second Team', 'DST')
    group_with(dashboard, second_team)
    create_issue(title: 'Investigate SSO login issue', due_date: @today)
    create_issue(title: 'Prepare launch comms', due_date: @today - 1)
    create_issue(team: second_team, title: 'Upgrade database', due_date: @today)

    get dashboard_path(dashboard, q: 'sso')

    assert_response :success
    assert_includes response.body, 'Investigate SSO login issue'
    assert_not_includes response.body, 'Prepare launch comms'
    assert_not_includes response.body, 'Upgrade database'
    assert_includes response.body, 'Nothing due today'
    assert_select '[data-testid=dashboard-counts]', text: /2 due today/
    assert_select '[data-testid=dashboard-counts]', text: /1 overdue/
  end

  test 'q finds an issue by identifier' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    issue = create_issue(title: 'Needle issue', due_date: @today)
    create_issue(title: 'Hay issue', due_date: @today)

    get dashboard_path(dashboard, q: issue.identifier)
    assert_includes response.body, 'Needle issue'
    assert_not_includes response.body, 'Hay issue'

    get dashboard_path(dashboard, q: issue.identifier.downcase)
    assert_includes response.body, 'Needle issue'
    assert_not_includes response.body, 'Hay issue'
  end

  test 'team narrows the rows and the header pills' do
    dashboard = @user.dashboards.create!(name: 'Today')
    second_team = member_team('Second Team', 'DST')
    group_with(dashboard, @team)
    group_with(dashboard, second_team)
    create_issue(title: 'First team issue', due_date: @today)
    create_issue(team: second_team, title: 'Second team issue', due_date: @today)
    create_issue(team: second_team, title: 'Second team overdue', due_date: @today - 1)

    get dashboard_path(dashboard, team: second_team.id)

    assert_response :success
    assert_includes response.body, 'Second team issue'
    assert_includes response.body, 'Second team overdue'
    assert_not_includes response.body, 'First team issue'
    assert_includes response.body, 'Nothing due today' # the @team group's empty line
    assert_select '[data-testid=dashboard-counts]', text: /1 due today/
    assert_select '[data-testid=dashboard-counts]', text: /1 overdue/
    assert_select 'select[name=team] option[selected][value=?]', second_team.id.to_s
  end

  test "a team id the user isn't in is ignored and leaks nothing" do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team, @other_team)
    create_issue(title: 'Visible issue', due_date: @today)
    create_issue(team: @other_team, title: 'Secret issue', due_date: @today)

    get dashboard_path(dashboard, team: @other_team.id)

    assert_response :success
    assert_includes response.body, 'Visible issue'
    assert_not_includes response.body, 'Secret issue'
    assert_select '[data-testid=dashboard-counts]', text: /1 due today/
    assert_select 'select[name=team] option[selected]', count: 0
    assert_select 'select[name=team] option', text: 'Other Team', count: 0
  end

  test 'filtering by team does not change the current team in the session' do
    dashboard = @user.dashboards.create!(name: 'Today')
    second_team = member_team('Second Team', 'DST')
    group_with(dashboard, second_team)

    get dashboard_path(dashboard)
    assert_equal @team.id, session[:current_team_id]

    get dashboard_path(dashboard, team: second_team.id)
    assert_equal @team.id, session[:current_team_id]

    get dashboard_path(dashboard, team: @other_team.id)
    assert_equal @team.id, session[:current_team_id]
  end

  test 'the header form lists only source teams and carries the filter and mine' do
    dashboard = @user.dashboards.create!(name: 'Today')
    second_team = member_team('Second Team', 'DST')
    member_team('Unused Team', 'DSU')
    project = second_team.projects.create!(name: 'Second Project')
    group_with(dashboard, @team)
    group_with(dashboard, project) # a Project source lists its owning team

    get dashboard_path(dashboard, filter: 'week', mine: 1, q: 'sso')

    assert_select "form[action='#{dashboard_path(dashboard)}'][method=get]" do
      assert_select 'input[type=hidden][name=filter][value=week]', count: 1
      assert_select 'input[type=hidden][name=mine][value="1"]', count: 1
      assert_select 'input[type=search][name=q][value=sso][autofocus]', count: 1
      assert_select 'select[name=team].cursor-pointer option', count: 3
      assert_select 'select[name=team] option[value=""]', text: 'All teams'
      assert_select 'select[name=team] option', text: 'Dash Team'
      assert_select 'select[name=team] option', text: 'Second Team'
      assert_select 'select[name=team] option', text: 'Unused Team', count: 0
    end
  end

  test 'the header form omits default filter, mine and autofocus' do
    dashboard = @user.dashboards.create!(name: 'Today')

    get dashboard_path(dashboard)

    assert_select 'input[type=hidden][name=filter]', count: 0
    assert_select 'input[type=hidden][name=mine]', count: 0
    assert_select 'input[type=search][name=q]', count: 1
    assert_select 'input[type=search][name=q][autofocus]', count: 0
    assert_select 'select[name=team] option', count: 1
  end

  test 'tabs and Mine-only keep q and team' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)

    get dashboard_path(dashboard, filter: 'week', mine: 1, q: 'sso', team: @team.id)

    assert_select "a[role=tab][href='#{dashboard_path(dashboard, filter: 'hot', mine: 1, q: 'sso', team: @team.id)}']",
                  text: 'Urgent / High'
    assert_select "a[role=tab][href='#{dashboard_path(dashboard, mine: 1, q: 'sso', team: @team.id)}']",
                  text: 'Due today'
    assert_select "a[aria-pressed=true][href='#{dashboard_path(dashboard, filter: 'week', q: 'sso', team: @team.id)}']",
                  text: /Mine only/
  end

  test 'blank q and team, as the form submits them, render unfiltered and drop out of tab links' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    create_issue(title: 'Any issue', due_date: @today)

    get dashboard_path(dashboard, filter: 'week', q: '', team: '')

    assert_response :success
    assert_includes response.body, 'Any issue'
    assert_select "a[role=tab][href='#{dashboard_path(dashboard, filter: 'hot')}']", text: 'Urgent / High'
    assert_select "a[aria-pressed=false][href='#{dashboard_path(dashboard, filter: 'week', mine: 1)}']",
                  text: /Mine only/
  end

  test 'filter, mine, q and team combine' do
    dashboard = @user.dashboards.create!(name: 'Today')
    second_team = member_team('Second Team', 'DST')
    group_with(dashboard, @team, second_team)
    create_issue(title: 'SSO urgent mine', priority: :urgent, assignee: @user)
    create_issue(title: 'SSO urgent theirs', priority: :urgent, assignee: @other_user)
    create_issue(title: 'SSO low mine', priority: :low, assignee: @user)
    create_issue(title: 'Other urgent mine', priority: :urgent, assignee: @user)
    create_issue(team: second_team, title: 'SSO urgent mine elsewhere', priority: :urgent, assignee: @user)

    get dashboard_path(dashboard, filter: 'hot', mine: 1, q: 'sso', team: @team.id)

    assert_includes response.body, 'SSO urgent mine'
    assert_not_includes response.body, 'SSO urgent theirs'
    assert_not_includes response.body, 'SSO low mine'
    assert_not_includes response.body, 'Other urgent mine'
    assert_not_includes response.body, 'SSO urgent mine elsewhere'
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
    assert_select '[data-testid=dashboard-group-inaccessible]'
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

    {
      'today' => 'Nothing due today 🎉',
      'week' => 'Nothing due this week',
      'hot' => 'No urgent or high-priority issues',
      'open' => 'No open issues'
    }.each do |filter, copy|
      get dashboard_path(dashboard, filter: filter)

      assert_includes response.body, copy, "filter=#{filter}"
    end
  end

  test 'an empty group mentions the user when Mine only is on' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group_with(dashboard, @team)
    create_issue(title: 'Someone else', due_date: @today, assignee: @other_user)

    get dashboard_path(dashboard, filter: 'week', mine: 1)

    assert_includes response.body, 'Nothing due this week assigned to you'
    assert_not_includes response.body, 'Someone else'
  end

  test 'a group whose sources are all inaccessible links to its edit modal' do
    dashboard = @user.dashboards.create!(name: 'Today')
    group = group_with(dashboard, @other_team)

    get dashboard_path(dashboard)

    assert_select '[data-testid=dashboard-group-inaccessible]',
                  text: %r{This group's teams/projects are no longer available\.} do
      assert_select "button[data-action='click->dashboard-group-form#open']" \
                    "[data-dashboard-group-form-url-param='#{dashboard_group_path(dashboard, group)}']" \
                    "[data-dashboard-group-form-method-param='patch']",
                    text: 'Edit group'
    end
    assert_not_includes response.body, 'Nothing due today'
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
    assert_includes response.body, 'Group teams and projects into one view'
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

  # Sources show every issue by default here; the assigned-to-me default has its own tests.
  def group_with(dashboard, *sources, include_all: true)
    dashboard.groups.create!(name: "Group #{dashboard.groups.count + 1}").tap do |group|
      sources.each { |source| group.sources.create!(source: source, include_all: include_all) }
    end
  end

  def member_team(name, identifier)
    @workspace.teams.create!(name: name, identifier: identifier).tap do |team|
      team.team_memberships.create!(user: @user)
    end
  end

  def create_issue(team: @team, title: "Issue #{SecureRandom.hex(3)}", **attrs)
    team.issues.create!(title: title, lane: team.lanes.first, creator: @user, **attrs)
  end
end
