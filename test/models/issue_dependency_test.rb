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
    @issue_c = @team.issues.create!(title: 'Issue C', lane: @lane, creator: @user)
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

  test 'default kind is blocks' do
    dep = IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    assert dep.blocks?
    assert_equal 'blocks', dep.reload.kind
  end

  test 'source and target read the same columns as blocking and blocked' do
    dep = IssueDependency.new(blocking_issue: @issue_a, blocked_issue: @issue_b, kind: :relates)
    assert_equal @issue_a, dep.source_issue
    assert_equal @issue_b, dep.target_issue
  end

  test 'rejects a direct blocks cycle' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    dep = IssueDependency.new(blocking_issue: @issue_b, blocked_issue: @issue_a)
    assert_not dep.valid?
    assert_includes dep.errors.full_messages, 'Would create a circular dependency'
  end

  test 'rejects a three-issue blocks cycle' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    IssueDependency.create!(blocking_issue: @issue_b, blocked_issue: @issue_c)
    dep = IssueDependency.new(blocking_issue: @issue_c, blocked_issue: @issue_a)
    assert_not dep.valid?
    assert_equal ['Would create a circular dependency'], dep.errors.full_messages
  end

  test 'cycle check only follows blocks edges' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    IssueDependency.create!(blocking_issue: @issue_b, blocked_issue: @issue_c, kind: :relates)
    dep = IssueDependency.new(blocking_issue: @issue_c, blocked_issue: @issue_a)
    assert dep.valid?, dep.errors.full_messages.join
  end

  test 'rejects a reverse pair of any kind' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    dep = IssueDependency.new(blocking_issue: @issue_b, blocked_issue: @issue_a, kind: :relates)
    assert_not dep.valid?
    assert_includes dep.errors.full_messages, 'These issues are already linked'
  end

  test 'relates links are not blocking dependencies' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b, kind: :relates)
    assert_empty @issue_a.blocking_dependencies
    assert_empty @issue_b.blocked_dependencies
    assert_empty @issue_b.blocking_issues
  end

  test 'remove_blocking_dependencies! keeps relates and duplicates links' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    relates = IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_c, kind: :relates)
    issue_d = @team.issues.create!(title: 'Issue D', lane: @lane, creator: @user)
    duplicates = IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: issue_d, kind: :duplicates)

    @issue_a.update!(completed_at: Time.current)
    @issue_a.remove_blocking_dependencies!

    assert_empty @issue_a.blocking_dependencies.reload
    assert_equal [relates, duplicates].sort_by(&:id), @issue_a.outgoing_links.reload.sort_by(&:id)
  end

  test 'destroying issue destroys links of every kind' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    IssueDependency.create!(blocking_issue: @issue_c, blocked_issue: @issue_a, kind: :relates)
    issue_d = @team.issues.create!(title: 'Issue D', lane: @lane, creator: @user)
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: issue_d, kind: :duplicates)

    assert_difference 'IssueDependency.count', -3 do
      @issue_a.destroy
    end
  end

  test 'related_issues returns the other issue in either direction' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b, kind: :relates)
    IssueDependency.create!(blocking_issue: @issue_c, blocked_issue: @issue_a, kind: :relates)
    assert_equal [@issue_b, @issue_c].sort_by(&:id), @issue_a.related_issues.sort_by(&:id)
    assert_equal [@issue_a], @issue_b.related_issues.to_a
  end

  test 'duplicate_of and duplicated_by' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b, kind: :duplicates)
    assert_equal @issue_b, @issue_a.duplicate_of
    assert_nil @issue_b.duplicate_of
    assert_equal [@issue_a], @issue_b.duplicated_by.to_a
  end
end
