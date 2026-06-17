require 'test_helper'

class IssueTeamMoverTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Mover', email: 'mover@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)

    @source = @workspace.teams.create!(name: 'Source', identifier: 'SRC')
    @source.team_memberships.create!(user: @user)
    @target = @workspace.teams.create!(name: 'Target', identifier: 'TGT')
    @target.team_memberships.create!(user: @user)

    @source_backlog = @source.lanes.find_by(name: 'Backlog')
    @project = @source.projects.create!(name: 'Source Project')
    @label = @source.labels.create!(name: 'bug', color: '#fff')

    @issue = @source.issues.create!(
      title: 'Movable', lane: @source_backlog, creator: @user,
      project: @project, assignee: @user
    )
    @issue.labels << @label
  end

  test 'renumbers from target team counter and changes identifier' do
    target_next = @target.issue_counter + 1

    assert IssueTeamMover.new(issue: @issue, target_team: @target, user: @user).call

    @issue.reload
    assert_equal @target, @issue.team
    assert_equal target_next, @issue.team_number
    assert_equal "TGT-#{target_next}", @issue.identifier
  end

  test 'remaps lane by name and clears project and labels' do
    target_backlog = @target.lanes.find_by(name: 'Backlog')

    assert IssueTeamMover.new(issue: @issue, target_team: @target, user: @user).call

    @issue.reload
    assert_equal target_backlog, @issue.lane
    assert_nil @issue.project
    assert_empty @issue.labels
  end

  test 'falls back to first lane when no name match exists' do
    @issue.update!(lane: @source.lanes.create!(name: 'Custom', position: 9))

    assert IssueTeamMover.new(issue: @issue, target_team: @target, user: @user).call

    @issue.reload
    assert_equal @target.lanes.order(:position).first, @issue.lane
  end

  test 'keeps assignee when they are a member of the target team' do
    assert IssueTeamMover.new(issue: @issue, target_team: @target, user: @user).call

    assert_equal @user, @issue.reload.assignee
  end

  test 'clears assignee when they are not a member of the target team' do
    other = User.create!(name: 'Other', email: 'other@example.com', password: 'password')
    @source.team_memberships.create!(user: other)
    @issue.update!(assignee: other)

    assert IssueTeamMover.new(issue: @issue, target_team: @target, user: @user).call

    assert_nil @issue.reload.assignee
  end

  test 'severs cross-team parent and child links' do
    parent = @source.issues.create!(title: 'Parent', lane: @source_backlog, creator: @user)
    child = @source.issues.create!(title: 'Child', lane: @source_backlog, creator: @user)
    @issue.update!(parent_issue: parent)
    child.update!(parent_issue: @issue)

    assert IssueTeamMover.new(issue: @issue, target_team: @target, user: @user).call

    assert_nil @issue.reload.parent_issue
    assert_nil child.reload.parent_issue
  end

  test 'records a paper_trail activity describing the team move' do
    assert IssueTeamMover.new(issue: @issue, target_team: @target, user: @user).call

    version = @issue.versions.last
    description = VersionDescriptionService.call(version)
    assert_includes description, 'moved from team'
    assert_includes description, 'Source'
    assert_includes description, 'Target'
    refute_includes description, 'changed status'
  end

  test 'fails when user does not belong to both teams' do
    stranger = User.create!(name: 'Stranger', email: 'stranger@example.com', password: 'password')

    mover = IssueTeamMover.new(issue: @issue, target_team: @target, user: stranger)

    assert_not mover.call
    assert mover.error.present?
    assert_equal @source, @issue.reload.team
  end

  test 'fails when target team is the current team' do
    mover = IssueTeamMover.new(issue: @issue, target_team: @source, user: @user)

    assert_not mover.call
    assert mover.error.present?
  end
end
