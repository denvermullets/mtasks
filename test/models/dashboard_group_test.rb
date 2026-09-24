require 'test_helper'

class DashboardGroupTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Group User', email: 'dashboard_group@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Group Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Group Team', identifier: 'DGT')
    @team.team_memberships.create!(user: @user)
    @project = @team.projects.create!(name: 'Launch project')
    @dashboard = @user.dashboards.create!(name: 'Today')
    @group = @dashboard.groups.create!(name: 'Launch')
  end

  test 'name is required' do
    assert_not @dashboard.groups.new(name: '').valid?
  end

  test 'defaults to a valid color' do
    assert_equal '#6366f1', @group.color
  end

  test 'color must be a six digit hex' do
    assert @dashboard.groups.new(name: 'Ok', color: '#A1b2C3').valid?

    %w[red #fff #1234567 123456 #12345g].each do |color|
      assert_not @dashboard.groups.new(name: 'Bad', color: color).valid?, "#{color} should be invalid"
    end
  end

  test 'can attach both a team and a project as sources' do
    @group.sources.create!(source: @team)
    @group.sources.create!(source: @project)

    assert_equal [@team.id], @group.team_ids
    assert_equal [@project.id], @group.project_ids
  end

  test 'adding the same source twice is invalid' do
    @group.sources.create!(source: @team)
    duplicate = @group.sources.new(source: @team)

    assert_not duplicate.valid?
  end

  test 'the same source can be used by different groups' do
    other_group = @dashboard.groups.create!(name: 'Customer')
    @group.sources.create!(source: @team)

    assert other_group.sources.new(source: @team).valid?
  end

  test 'rejects source types other than Team and Project' do
    label = @team.labels.create!(name: 'bug', color: '#ff0000')
    source = @group.sources.new(source: label)

    assert_not source.valid?
    assert source.errors[:source_type].any?
  end

  test 'destroying a group destroys its sources' do
    @group.sources.create!(source: @team)

    assert_difference -> { DashboardGroupSource.count } => -1 do
      @group.destroy
    end
  end
end
