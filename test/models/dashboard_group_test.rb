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

  # --- replace_sources! ------------------------------------------------------

  test 'replace_sources! adds and removes sources and keeps the ones still listed' do
    kept = @group.sources.create!(source: @project)
    @group.sources.create!(source: @team)
    other_project = @team.projects.create!(name: 'Other project')

    @group.replace_sources!(team_ids: [], project_ids: [@project.id, other_project.id])

    assert_equal [], @group.team_ids
    assert_equal [@project.id, other_project.id].sort, @group.project_ids.sort
    assert DashboardGroupSource.exists?(kept.id), 'a source that stays should not be recreated'
  end

  test 'replace_sources! with empty lists clears everything' do
    @group.sources.create!(source: @team)
    @group.sources.create!(source: @project)

    @group.replace_sources!(team_ids: [], project_ids: [])

    assert_empty @group.sources.reload
  end

  test 'replace_sources! is idempotent' do
    @group.replace_sources!(team_ids: [@team.id], project_ids: [@project.id])

    assert_no_difference -> { DashboardGroupSource.count } do
      @group.replace_sources!(team_ids: [@team.id], project_ids: [@project.id])
    end
  end

  test 'sources default to assigned-to-me' do
    @group.replace_sources!(team_ids: [@team.id], project_ids: [@project.id])

    assert_equal [], @group.all_team_ids
    assert_equal [], @group.all_project_ids
  end

  test 'replace_sources! sets and clears include_all on existing sources' do
    @group.replace_sources!(team_ids: [@team.id], project_ids: [@project.id], all_team_ids: [@team.id])
    assert_equal [@team.id], @group.all_team_ids
    assert_equal [], @group.all_project_ids

    @group.replace_sources!(team_ids: [@team.id], project_ids: [@project.id], all_project_ids: [@project.id])
    assert_equal [], @group.all_team_ids
    assert_equal [@project.id], @group.all_project_ids
  end

  test 'replace_sources! ignores include_all ids that are not sources' do
    @group.replace_sources!(team_ids: [], project_ids: [@project.id], all_team_ids: [@team.id])

    assert_equal [], @group.team_ids
    assert_equal [], @group.all_team_ids
  end

  # --- move! -----------------------------------------------------------------

  test 'move! swaps with the neighbour and renumbers from 1' do
    a = @group
    b = @dashboard.groups.create!(name: 'B', position: 5)
    c = @dashboard.groups.create!(name: 'C', position: 9)

    b.move!('down')

    assert_equal [a, c, b], @dashboard.groups.reload.to_a
    assert_equal [1, 2, 3], @dashboard.groups.map(&:position)
  end

  test 'move! at an edge changes nothing' do
    b = @dashboard.groups.create!(name: 'B', position: 1)

    assert_equal [@group, b], @dashboard.groups.reload.to_a
    @group.move!('up')
    b.move!('down')

    assert_equal [@group, b], @dashboard.groups.reload.to_a
  end
end
