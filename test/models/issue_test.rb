require 'test_helper'

class IssueTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'issue_model@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'IST')
    @team.team_memberships.create!(user: @user)
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @done = @team.lanes.create!(name: 'Done', position: 1)
  end

  test 'title is required' do
    issue = @team.issues.new(title: '', lane: @backlog, creator: @user)
    assert_not issue.valid?
  end

  test 'assigns team_number on create' do
    issue = @team.issues.create!(title: 'First', lane: @backlog, creator: @user)
    assert_not_nil issue.team_number
  end

  test 'identifier combines team identifier and number' do
    issue = @team.issues.create!(title: 'Test', lane: @backlog, creator: @user)
    assert_equal "IST-#{issue.team_number}", issue.identifier
  end

  # Blocking relationships
  test 'blocked_issues returns issues this one blocks' do
    issue_a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
    issue_b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
    IssueDependency.create!(blocking_issue: issue_a, blocked_issue: issue_b)

    assert_includes issue_a.blocked_issues, issue_b
  end

  test 'blocking_issues returns issues that block this one' do
    issue_a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
    issue_b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
    IssueDependency.create!(blocking_issue: issue_a, blocked_issue: issue_b)

    assert_includes issue_b.blocking_issues, issue_a
  end

  test 'remove_blocking_dependencies! removes blocking deps when completed' do
    issue_a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
    issue_b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
    IssueDependency.create!(blocking_issue: issue_a, blocked_issue: issue_b)

    issue_a.update!(completed_at: Time.current)
    issue_a.remove_blocking_dependencies!
    assert_equal 0, issue_a.reload.blocking_dependencies.count
  end

  test 'remove_blocking_dependencies! does not remove blocked_by dependencies' do
    issue_a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
    issue_b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
    IssueDependency.create!(blocking_issue: issue_b, blocked_issue: issue_a)

    issue_a.update!(completed_at: Time.current)
    issue_a.remove_blocking_dependencies!
    assert_equal 1, issue_a.reload.blocked_dependencies.count
  end

  # Project association
  test 'can belong to a project' do
    project = @team.projects.create!(name: 'My Project')
    issue = @team.issues.create!(title: 'Test', lane: @backlog, creator: @user, project: project)

    assert_equal project, issue.project
    assert_includes project.issues, issue
  end

  # Scopes
  test 'not_archived excludes archived issues' do
    issue = @team.issues.create!(title: 'Archived', lane: @backlog, creator: @user, archived_at: Time.current)
    assert_not_includes @team.issues.not_archived, issue
  end

  test 'not_completed excludes completed issues' do
    issue = @team.issues.create!(title: 'Completed', lane: @backlog, creator: @user, completed_at: Time.current)
    assert_not_includes @team.issues.not_completed, issue
  end

  test 'apply_lane_timestamps! sets canceled_at when moving to a Cancelled lane' do
    cancelled = @team.lanes.create!(name: 'Cancelled', position: 2)
    issue = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)

    issue.lane_id = cancelled.id
    issue.apply_lane_timestamps!

    assert_not_nil issue.canceled_at
    assert_nil issue.completed_at
  end

  test 'apply_lane_timestamps! also matches a Canceled (US spelling) lane' do
    canceled = @team.lanes.create!(name: 'Canceled', position: 2)
    issue = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)

    issue.lane_id = canceled.id
    issue.apply_lane_timestamps!

    assert_not_nil issue.canceled_at
  end

  test 'apply_lane_timestamps! clears canceled_at when moving away from a Cancelled lane' do
    cancelled = @team.lanes.create!(name: 'Cancelled', position: 2)
    issue = @team.issues.create!(
      title: 'A', lane: cancelled, creator: @user, canceled_at: 1.day.ago
    )

    issue.lane_id = @backlog.id
    issue.apply_lane_timestamps!

    assert_nil issue.canceled_at
  end
end
