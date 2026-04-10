require 'test_helper'

class IssueReferenceServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'ref_svc@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'TST')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)

    @issue_a = @team.issues.create!(title: 'Issue A', lane: @lane, creator: @user)
    @issue_b = @team.issues.create!(title: 'Issue B', lane: @lane, creator: @user)
    @issue_c = @team.issues.create!(title: 'Issue C', lane: @lane, creator: @user)
  end

  test 'creates reference when text contains a valid issue identifier' do
    assert_difference 'IssueReference.count', 1 do
      IssueReferenceService.call(
        source_issue: @issue_a,
        text: "see TST-#{@issue_b.team_number} for details",
        source_type: 'comment',
        user: @user
      )
    end

    ref = IssueReference.last
    assert_equal @issue_a, ref.source_issue
    assert_equal @issue_b, ref.referenced_issue
    assert_equal 'comment', ref.source_type
    assert_equal @user, ref.user
  end

  test 'creates multiple references for multiple identifiers' do
    assert_difference 'IssueReference.count', 2 do
      IssueReferenceService.call(
        source_issue: @issue_a,
        text: "related to TST-#{@issue_b.team_number} and TST-#{@issue_c.team_number}",
        source_type: 'description',
        user: @user
      )
    end
  end

  test 'does not create duplicate references' do
    IssueReferenceService.call(
      source_issue: @issue_a,
      text: "see TST-#{@issue_b.team_number}",
      source_type: 'comment',
      user: @user
    )

    assert_no_difference 'IssueReference.count' do
      IssueReferenceService.call(
        source_issue: @issue_a,
        text: "see TST-#{@issue_b.team_number} again",
        source_type: 'comment',
        user: @user
      )
    end
  end

  test 'does not create self-reference' do
    assert_no_difference 'IssueReference.count' do
      IssueReferenceService.call(
        source_issue: @issue_a,
        text: "see TST-#{@issue_a.team_number}",
        source_type: 'description',
        user: @user
      )
    end
  end

  test 'ignores identifiers from other teams' do
    assert_no_difference 'IssueReference.count' do
      IssueReferenceService.call(
        source_issue: @issue_a,
        text: 'see FAKE-999',
        source_type: 'comment',
        user: @user
      )
    end
  end

  test 'handles blank text' do
    assert_no_difference 'IssueReference.count' do
      IssueReferenceService.call(
        source_issue: @issue_a,
        text: '',
        source_type: 'description',
        user: @user
      )
    end
  end
end
