require 'test_helper'

class IssueDependencyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'dep_model@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'DEP')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)

    @issue_a = @team.issues.create!(title: 'Issue A', lane: @lane, creator: @user)
    @issue_b = @team.issues.create!(title: 'Issue B', lane: @lane, creator: @user)
  end

  test 'valid dependency' do
    dep = IssueDependency.new(blocking_issue: @issue_a, blocked_issue: @issue_b)
    assert dep.valid?
  end

  test 'cannot block self' do
    dep = IssueDependency.new(blocking_issue: @issue_a, blocked_issue: @issue_a)
    assert_not dep.valid?
    assert_includes dep.errors.full_messages.join, 'cannot block itself'
  end

  test 'duplicate dependency is invalid' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    dup = IssueDependency.new(blocking_issue: @issue_a, blocked_issue: @issue_b)
    assert_not dup.valid?
  end

  test 'issues must be in the same team' do
    other_workspace = Workspace.create!(name: 'Other WS', owner: @user)
    other_team = other_workspace.teams.create!(name: 'Other', identifier: 'OTH')
    other_lane = other_team.lanes.create!(name: 'Backlog', position: 0)
    other_issue = other_team.issues.create!(title: 'Other', lane: other_lane, creator: @user)

    dep = IssueDependency.new(blocking_issue: @issue_a, blocked_issue: other_issue)
    assert_not dep.valid?
    assert_includes dep.errors.full_messages.join, 'same team'
  end

  test 'destroying issue destroys its blocking dependencies' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    assert_difference 'IssueDependency.count', -1 do
      @issue_a.destroy
    end
  end

  test 'destroying issue destroys its blocked dependencies' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    assert_difference 'IssueDependency.count', -1 do
      @issue_b.destroy
    end
  end
end
