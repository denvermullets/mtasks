require 'test_helper'

class IssueReferenceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'ref_model@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'REF')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)

    @issue_a = @team.issues.create!(title: 'Issue A', lane: @lane, creator: @user)
    @issue_b = @team.issues.create!(title: 'Issue B', lane: @lane, creator: @user)
  end

  test 'valid reference' do
    ref = IssueReference.new(source_issue: @issue_a, referenced_issue: @issue_b, user: @user, source_type: 'comment')
    assert ref.valid?
  end

  test 'cannot reference self' do
    ref = IssueReference.new(source_issue: @issue_a, referenced_issue: @issue_a, user: @user, source_type: 'comment')
    assert_not ref.valid?
    assert_includes ref.errors.full_messages.join, 'cannot reference itself'
  end

  test 'duplicate reference with same source_type is invalid' do
    IssueReference.create!(source_issue: @issue_a, referenced_issue: @issue_b, user: @user, source_type: 'comment')
    dup = IssueReference.new(source_issue: @issue_a, referenced_issue: @issue_b, user: @user, source_type: 'comment')
    assert_not dup.valid?
  end

  test 'same reference with different source_type is valid' do
    IssueReference.create!(source_issue: @issue_a, referenced_issue: @issue_b, user: @user, source_type: 'comment')
    ref = IssueReference.new(source_issue: @issue_a, referenced_issue: @issue_b, user: @user,
                             source_type: 'description')
    assert ref.valid?
  end

  test 'source_type must be comment or description' do
    ref = IssueReference.new(source_issue: @issue_a, referenced_issue: @issue_b, user: @user, source_type: 'invalid')
    assert_not ref.valid?
  end

  test 'source_type is required' do
    ref = IssueReference.new(source_issue: @issue_a, referenced_issue: @issue_b, user: @user, source_type: nil)
    assert_not ref.valid?
  end

  test 'destroying source issue destroys its outgoing references' do
    IssueReference.create!(source_issue: @issue_a, referenced_issue: @issue_b, user: @user, source_type: 'comment')
    assert_difference 'IssueReference.count', -1 do
      @issue_a.destroy
    end
  end

  test 'destroying referenced issue destroys its incoming references' do
    IssueReference.create!(source_issue: @issue_a, referenced_issue: @issue_b, user: @user, source_type: 'comment')
    assert_difference 'IssueReference.count', -1 do
      @issue_b.destroy
    end
  end
end
