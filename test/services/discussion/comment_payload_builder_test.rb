require 'test_helper'

module Discussion
  class CommentPayloadBuilderTest < ActiveSupport::TestCase
    setup do
      @author = User.create!(name: 'Casey Smith', email: 'casey@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @author)
      @team = @workspace.teams.create!(name: 'T', identifier: 'CPB')
      @team.team_memberships.create!(user: @author)
      @project = @team.projects.create!(name: 'Proj')
    end

    test 'returns body and data for a project-level comment' do
      comment = @project.comments.create!(user: @author, body: 'hello world')
      result = CommentPayloadBuilder.call(comment: comment)

      assert_equal 'Casey Smith commented in JAIT', result[:body]
      data = result[:data]
      assert_equal 'mtasks', data[:source]
      assert_equal 'project.commented', data[:event_type]
      assert_match(%r{\Ahttp://[^/]+/teams/#{@team.id}/projects/#{@project.id}/discussion\z}, data[:source_url])
      assert_equal 'casey@example.com', data[:actor_email]
      assert_equal 'Casey Smith', data[:actor_name]
      assert_equal 'casey', data[:actor_username]
      assert_equal comment.id, data[:comment_id]
      assert_equal 'hello world', data[:comment_body]
      assert_equal 'Proj', data[:project_name]
      assert_nil data[:identifier]
      assert_nil data[:issue_id]
    end

    test 'includes issue identifier and team_slug when comment belongs to an issue' do
      lane = @team.lanes.create!(name: 'Backlog', position: 0)
      issue = @team.issues.create!(title: 'I', creator: @author, lane: lane, project: @project)
      comment = issue.comments.create!(user: @author, body: 'thread reply')

      data = CommentPayloadBuilder.call(comment: comment)[:data]
      assert_equal 'issue.commented', data[:event_type]
      assert_equal issue.id, data[:issue_id]
      assert_equal issue.identifier, data[:identifier]
      assert_equal 'I', data[:title]
      assert_equal 'CPB', data[:team_slug]
      assert_equal 'Proj', data[:project_name]
      assert_match(%r{\Ahttp://[^/]+/teams/#{@team.id}/issues/#{issue.id}\z}, data[:source_url])
    end

    test 'rewrites @Name mention to @email when target user has a hourglass user map' do
      target = User.create!(name: 'Robin Doe', email: 'robin@example.com', password: 'password')
      @team.team_memberships.create!(user: target)
      HourglassUserMap.create!(mtasks_user: target, hourglass_user_id: 'hu_robin', email: 'robin@example.com',
                               last_synced_at: Time.current)

      comment = @project.comments.create!(user: @author, body: 'hey @Robin Doe ping')
      data = CommentPayloadBuilder.call(comment: comment)[:data]
      assert_equal 'hey @robin@example.com ping', data[:comment_body]
    end

    test 'leaves @Name alone when no hourglass user map exists' do
      target = User.create!(name: 'Robin Doe', email: 'robin@example.com', password: 'password')
      @team.team_memberships.create!(user: target)

      comment = @project.comments.create!(user: @author, body: 'hi @Robin Doe')
      data = CommentPayloadBuilder.call(comment: comment)[:data]
      assert_equal 'hi @Robin Doe', data[:comment_body]
    end
  end
end
