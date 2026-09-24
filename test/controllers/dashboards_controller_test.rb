require 'test_helper'

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Dash User', email: 'dashboards_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Dash Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Dash Team', identifier: 'DSC')
    @team.team_memberships.create!(user: @user)

    @other_user = User.create!(name: 'Other', email: 'dashboards_other@example.com', password: 'password')
    @other_dashboard = @other_user.dashboards.create!(name: 'Not yours')

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

  test 'show renders the stub and highlights the dashboard in the sidebar' do
    dashboard = @user.dashboards.create!(name: 'Today')

    get dashboard_path(dashboard)

    assert_response :success
    assert_includes response.body, 'Groups coming soon'
    assert_select "a.bg-foreground[href='#{dashboard_path(dashboard)}']"
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
end
