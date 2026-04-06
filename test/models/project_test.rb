require 'test_helper'

class ProjectTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'proj_model@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'PJT')
    @team.team_memberships.create!(user: @user)
  end

  test 'valid project with name' do
    project = @team.projects.new(name: 'My Project')
    assert project.valid?
  end

  test 'name is required' do
    project = @team.projects.new(name: '')
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test 'valid statuses' do
    Project::STATUSES.each do |status|
      project = @team.projects.new(name: 'Test', status: status)
      assert project.valid?, "Expected status '#{status}' to be valid"
    end
  end

  test 'invalid status' do
    project = @team.projects.new(name: 'Test', status: 'invalid')
    assert_not project.valid?
  end

  test 'nullifies issues on destroy' do
    project = @team.projects.create!(name: 'My Project')
    lane = @team.lanes.create!(name: 'Backlog', position: 0)
    issue = @team.issues.create!(title: 'Test', lane: lane, creator: @user, project: project)

    project.destroy
    issue.reload
    assert_nil issue.project_id
  end

  test 'belongs to lead' do
    project = @team.projects.create!(name: 'Led Project', lead: @user)
    assert_equal @user, project.lead
  end

  test 'priority enum' do
    project = @team.projects.create!(name: 'Urgent', priority: :urgent)
    assert project.urgent?

    project.update!(priority: :low)
    assert project.low?
  end
end
