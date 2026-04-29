require 'test_helper'

class CommentTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'C User', email: 'comment_test@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'C WS', owner: @user)
    @team = @workspace.teams.create!(name: 'C Team', identifier: 'CMT')
    @team.team_memberships.create!(user: @user)
    @backlog = @team.lanes.find_by(name: 'Backlog') || @team.lanes.first
    @project = @team.projects.create!(name: 'P')
    @issue = @team.issues.create!(title: 'I', lane: @backlog, creator: @user, project: @project)
  end

  test 'should belong to issue' do
    comment = Comment.new
    assert_respond_to comment, :issue
  end

  test 'should belong to project' do
    comment = Comment.new
    assert_respond_to comment, :project
  end

  test 'should belong to user' do
    comment = Comment.new
    assert_respond_to comment, :user
  end

  test 'should require body or files' do
    comment = Comment.new(user: @user, issue: @issue)
    assert_not comment.valid?
    assert_includes comment.errors[:base], 'Comment must have text or an attachment'
  end

  test 'issue-only comment is valid' do
    comment = Comment.new(user: @user, issue: @issue, body: 'hi')
    assert comment.valid?
  end

  test 'project-only comment is valid' do
    comment = Comment.new(user: @user, project: @project, body: 'hi')
    assert comment.valid?
  end

  test 'comment with both issue and project is invalid' do
    comment = Comment.new(user: @user, issue: @issue, project: @project, body: 'hi')
    assert_not comment.valid?
    assert_includes comment.errors[:base], 'Comment must belong to exactly one of issue or project'
  end

  test 'comment with neither issue nor project is invalid' do
    comment = Comment.new(user: @user, body: 'hi')
    assert_not comment.valid?
    assert_includes comment.errors[:base], 'Comment must belong to exactly one of issue or project'
  end

  test 'CHECK constraint blocks raw insert with both owners' do
    sql = <<~SQL.squish
      INSERT INTO comments (body, user_id, issue_id, project_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, NOW(), NOW())
    SQL

    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([sql, 'x', @user.id, @issue.id, @project.id])
      )
    end
  end
end
