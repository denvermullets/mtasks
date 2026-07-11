require 'test_helper'

class CommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Comment User', email: 'comment_user@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Comment Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Comment Team', identifier: 'CMT')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)
    @issue = @team.issues.create!(title: 'Commentable issue', lane: @lane, creator: @user)
  end

  test 'create requires authentication' do
    assert_no_difference 'Comment.count' do
      post team_issue_comments_path(@team, @issue), params: { comment: { body: 'Hello' } }
    end

    assert_redirected_to new_session_path
  end

  test 'destroy requires authentication' do
    comment = @issue.comments.create!(user: @user, body: 'Existing comment')

    assert_no_difference 'Comment.count' do
      delete team_issue_comment_path(@team, @issue, comment)
    end

    assert_redirected_to new_session_path
  end

  test 'create adds a comment for an authenticated member' do
    sign_in_as(@user)

    assert_difference 'Comment.count', 1 do
      post team_issue_comments_path(@team, @issue), params: { comment: { body: 'Hello' } }
    end

    assert_equal 'Hello', @issue.comments.last.body
    assert_equal @user, @issue.comments.last.user
  end

  test 'destroy removes the authors own comment' do
    sign_in_as(@user)
    comment = @issue.comments.create!(user: @user, body: 'Existing comment')

    assert_difference 'Comment.count', -1 do
      delete team_issue_comment_path(@team, @issue, comment)
    end
  end
end
