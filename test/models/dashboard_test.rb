require 'test_helper'

class DashboardTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Dash User', email: 'dashboard_model@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Dash Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Dash Team', identifier: 'DSH')
    @team.team_memberships.create!(user: @user)
  end

  test 'name is required' do
    dashboard = @user.dashboards.new(name: '')
    assert_not dashboard.valid?
  end

  test 'name is limited to 80 characters' do
    assert_not @user.dashboards.new(name: 'a' * 81).valid?
    assert @user.dashboards.new(name: 'a' * 80).valid?
  end

  test 'groups are ordered by position then id' do
    dashboard = @user.dashboards.create!(name: 'Today')
    second = dashboard.groups.create!(name: 'Second', position: 1)
    first = dashboard.groups.create!(name: 'First', position: 0)
    third = dashboard.groups.create!(name: 'Third', position: 1)

    assert_equal [first, second, third], dashboard.groups.reload.to_a
  end

  test 'user dashboards are ordered by position' do
    later = @user.dashboards.create!(name: 'Later', position: 2)
    sooner = @user.dashboards.create!(name: 'Sooner', position: 1)

    assert_equal [sooner, later], @user.dashboards.reload.to_a
  end

  test 'destroying a dashboard destroys its groups and their sources' do
    dashboard = @user.dashboards.create!(name: 'Launch')
    group = dashboard.groups.create!(name: 'Customer')
    group.sources.create!(source: @team)

    assert_difference -> { DashboardGroup.count } => -1, -> { DashboardGroupSource.count } => -1 do
      dashboard.destroy
    end
  end

  test 'destroying a user destroys their dashboards' do
    other = User.create!(name: 'Other', email: 'dashboard_other@example.com', password: 'password')
    other.dashboards.create!(name: 'Mine')

    assert_difference -> { Dashboard.count } => -1 do
      other.destroy
    end
  end
end
