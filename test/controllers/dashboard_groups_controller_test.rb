require 'test_helper'

class DashboardGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Group User', email: 'dashboard_groups_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Group Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Group Team', identifier: 'DGC')
    @team.team_memberships.create!(user: @user)
    @project = @team.projects.create!(name: 'Launch project')

    @other_user = User.create!(name: 'Other', email: 'dashboard_groups_other@example.com', password: 'password')
    @other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'DGX')
    @other_team.team_memberships.create!(user: @other_user)
    @other_project = @other_team.projects.create!(name: 'Secret project')
    @other_dashboard = @other_user.dashboards.create!(name: 'Not yours')
    @other_group = @other_dashboard.groups.create!(name: 'Their group')

    @dashboard = @user.dashboards.create!(name: 'Today')

    sign_in_as(@user)
  end

  # --- create ----------------------------------------------------------------

  test 'create appends a group with its sources and redirects to the dashboard' do
    @dashboard.groups.create!(name: 'Existing', position: 3)

    assert_difference -> { @dashboard.groups.count }, 1 do
      post dashboard_groups_path(@dashboard), params: group_params(description: 'All launch work')
    end

    group = @dashboard.groups.order(:id).last
    assert_redirected_to dashboard_path(@dashboard)
    assert_equal 'Launch', group.name
    assert_equal 'All launch work', group.description
    assert_equal '#ec4899', group.color
    assert_equal 4, group.position
    assert_equal [@team.id], group.team_ids
    assert_equal [@project.id], group.project_ids
  end

  test 'create keeps the active filter, mine, search and team params in the redirect' do
    post dashboard_groups_path(@dashboard, filter: 'week', mine: 1, q: 'sso', team: @team.id), params: group_params

    assert_redirected_to dashboard_path(@dashboard, filter: 'week', mine: 1, q: 'sso', team: @team.id)
  end

  test 'create drops blank search and team params from the redirect' do
    post dashboard_groups_path(@dashboard, filter: 'week', q: '', team: ''), params: group_params

    assert_redirected_to dashboard_path(@dashboard, filter: 'week')
  end

  test 'create with a blank name responds 422 with the modal open' do
    assert_no_difference -> { DashboardGroup.count } do
      post dashboard_groups_path(@dashboard), params: group_params(name: '')
    end

    assert_response :unprocessable_entity
    assert_includes response.body, 'Name can&#39;t be blank'
    assert_select '#dashboard_group_form_modal:not(.hidden)'
    # The page behind the modal is the pristine dashboard, not a phantom card.
    assert_includes response.body, 'No groups yet'
  end

  test 'create drops team and project ids the user cannot use' do
    archived = @workspace.teams.create!(name: 'Old Team', identifier: 'DGA', archived_at: Time.current)
    archived.team_memberships.create!(user: @user)

    post dashboard_groups_path(@dashboard), params: group_params(
      team_ids: [@team.id, @other_team.id, archived.id, 999_999],
      project_ids: [@project.id, @other_project.id, 999_999]
    )

    group = @dashboard.groups.order(:id).last
    assert_redirected_to dashboard_path(@dashboard)
    assert_equal [@team.id], group.team_ids
    assert_equal [@project.id], group.project_ids
  end

  # --- update ----------------------------------------------------------------

  test 'update replaces the sources and attributes' do
    group = group_with(@team, @project)
    second_project = @team.projects.create!(name: 'Second project')

    patch dashboard_group_path(@dashboard, group), params: group_params(
      name: 'Customer', color: '#10b981', team_ids: [], project_ids: [second_project.id]
    )

    assert_redirected_to dashboard_path(@dashboard)
    group.reload
    assert_equal 'Customer', group.name
    assert_equal '#10b981', group.color
    assert_equal [], group.team_ids
    assert_equal [second_project.id], group.project_ids
  end

  test 'update with only the blank checkbox entries clears every source' do
    group = group_with(@team, @project)

    patch dashboard_group_path(@dashboard, group), params: group_params(team_ids: [''], project_ids: [''])

    assert_redirected_to dashboard_path(@dashboard)
    assert_empty group.sources.reload
  end

  test 'update with a blank name responds 422 and leaves the group untouched' do
    group = group_with(@team, @project)

    patch dashboard_group_path(@dashboard, group), params: group_params(name: '', team_ids: [], project_ids: [])

    assert_response :unprocessable_entity
    group.reload
    assert_equal 'Group 1', group.name
    assert_equal [@team.id], group.team_ids
    assert_equal [@project.id], group.project_ids
  end

  # --- destroy ---------------------------------------------------------------

  test 'destroy removes the group and its sources' do
    group = group_with(@team, @project)

    assert_difference -> { DashboardGroup.count } => -1, -> { DashboardGroupSource.count } => -2 do
      delete dashboard_group_path(@dashboard, group, filter: 'hot')
    end

    assert_redirected_to dashboard_path(@dashboard, filter: 'hot')
  end

  # --- move ------------------------------------------------------------------

  test 'move down swaps with the next group and the order persists' do
    a, b, c = %w[A B C].each_with_index.map { |name, i| @dashboard.groups.create!(name: name, position: i + 1) }

    patch move_dashboard_group_path(@dashboard, a), params: { direction: 'down' }

    assert_redirected_to dashboard_path(@dashboard)
    assert_equal [b, a, c], @dashboard.groups.reload.to_a
    assert_equal [1, 2, 3], @dashboard.groups.map(&:position)
  end

  test 'move up swaps with the previous group' do
    a, b = %w[A B].each_with_index.map { |name, i| @dashboard.groups.create!(name: name, position: i + 1) }

    patch move_dashboard_group_path(@dashboard, b), params: { direction: 'up' }

    assert_equal [b, a], @dashboard.groups.reload.to_a
  end

  test 'move at the edges is a no-op' do
    a, b = %w[A B].each_with_index.map { |name, i| @dashboard.groups.create!(name: name, position: i + 1) }

    patch move_dashboard_group_path(@dashboard, a), params: { direction: 'up' }
    patch move_dashboard_group_path(@dashboard, b), params: { direction: 'down' }

    assert_equal [a, b], @dashboard.groups.reload.to_a
  end

  test 'move heals groups that share a position' do
    a = @dashboard.groups.create!(name: 'A', position: 0)
    b = @dashboard.groups.create!(name: 'B', position: 0)

    patch move_dashboard_group_path(@dashboard, a), params: { direction: 'down' }

    assert_equal [b, a], @dashboard.groups.reload.to_a
    assert_equal [1, 2], @dashboard.groups.map(&:position)
  end

  test 'move with an unknown direction is a bad request' do
    group = @dashboard.groups.create!(name: 'A')

    patch move_dashboard_group_path(@dashboard, group), params: { direction: 'sideways' }

    assert_response :bad_request
  end

  # --- access ----------------------------------------------------------------

  test "another user's dashboard or group is not found" do
    post dashboard_groups_path(@other_dashboard), params: group_params
    assert_response :not_found
    assert_equal 1, @other_dashboard.groups.count

    patch dashboard_group_path(@other_dashboard, @other_group), params: group_params(name: 'Hijacked')
    assert_response :not_found

    patch move_dashboard_group_path(@other_dashboard, @other_group), params: { direction: 'down' }
    assert_response :not_found

    delete dashboard_group_path(@other_dashboard, @other_group)
    assert_response :not_found

    # Their group id through my dashboard is just as invisible.
    patch dashboard_group_path(@dashboard, @other_group), params: group_params(name: 'Hijacked')
    assert_response :not_found

    assert_equal 'Their group', @other_group.reload.name
  end

  # --- page wiring -----------------------------------------------------------

  test 'show renders the add-group trigger, the card menu and the modal pick lists' do
    group = group_with(@team)
    completed = @team.projects.create!(name: 'Shipped project', status: 'completed')
    @team.projects.create!(name: 'Old project', status: 'completed')
    group.sources.create!(source: completed)

    get dashboard_path(@dashboard, filter: 'week', q: 'sso', team: @team.id)

    assert_response :success
    kept = { filter: 'week', q: 'sso', team: @team.id }
    assert_select "[data-dashboard-group-form-url-param='#{dashboard_groups_path(@dashboard, kept)}']"
    assert_select "[data-dashboard-group-form-url-param='#{dashboard_group_path(@dashboard, group, kept)}']" \
                  "[data-dashboard-group-form-team-ids-param='[#{@team.id}]']"
    assert_select "form[action='#{move_dashboard_group_path(@dashboard, group, kept)}']", count: 2
    assert_select "input[type=checkbox][value='#{@team.id}'][name='dashboard_group[team_ids][]']"
    assert_select "label[data-completed=true] input[value='#{completed.id}']"
    assert_not_includes response.body, 'Old project'
    assert_not_includes response.body, 'Secret project'
  end

  private

  def group_params(**overrides)
    defaults = { name: 'Launch', color: '#ec4899', team_ids: [@team.id], project_ids: [@project.id] }
    { dashboard_group: defaults.merge(overrides) }
  end

  def group_with(*sources)
    @dashboard.groups.create!(name: "Group #{@dashboard.groups.count + 1}").tap do |group|
      sources.each { |source| group.sources.create!(source: source) }
    end
  end
end
