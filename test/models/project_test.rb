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

  test 'valid roadmap commitments' do
    Project::ROADMAP_COMMITMENTS.each do |commitment|
      project = @team.projects.new(name: 'Test', roadmap_commitment: commitment)
      assert project.valid?, "Expected commitment '#{commitment}' to be valid"
    end
  end

  test 'nil roadmap commitment is allowed' do
    project = @team.projects.new(name: 'Test', roadmap_commitment: nil)
    assert project.valid?
  end

  test 'invalid roadmap commitment is rejected' do
    project = @team.projects.new(name: 'Test', roadmap_commitment: 'soon')
    assert_not project.valid?
    assert_includes project.errors[:roadmap_commitment], 'is not included in the list'
  end

  test 'on_roadmap scope excludes projects with nil commitment' do
    on = @team.projects.create!(name: 'On', roadmap_commitment: 'now')
    @team.projects.create!(name: 'Off', roadmap_commitment: nil)

    ids = @team.projects.on_roadmap.pluck(:id)
    assert_includes ids, on.id
    assert_equal 1, ids.length
  end

  test 'not_completed scope excludes completed projects but keeps nil and other statuses' do
    completed = @team.projects.create!(name: 'Done', status: 'completed')
    cancelled = @team.projects.create!(name: 'Stopped', status: 'cancelled')
    started = @team.projects.create!(name: 'Going', status: 'started')
    no_status = @team.projects.create!(name: 'New', status: nil)

    ids = @team.projects.not_completed.pluck(:id)
    assert_not_includes ids, completed.id
    assert_includes ids, cancelled.id
    assert_includes ids, started.id
    assert_includes ids, no_status.id
  end

  test 'in_commitment scope orders by due_date nulls last then id' do
    late = @team.projects.create!(name: 'Late', roadmap_commitment: 'now', due_date: Date.new(2030, 6, 1))
    early = @team.projects.create!(name: 'Early', roadmap_commitment: 'now', due_date: Date.new(2030, 1, 1))
    no_date = @team.projects.create!(name: 'No date', roadmap_commitment: 'now', due_date: nil)

    ids = @team.projects.in_commitment('now').pluck(:id)
    assert_equal [early.id, late.id, no_date.id], ids
  end
end
