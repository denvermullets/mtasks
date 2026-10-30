require 'test_helper'

module Api
  module V1
    class CommentsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_comments@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'APC')
        @team.team_memberships.create!(user: @user)

        @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
        @issue = @team.issues.create!(title: 'Existing issue', lane: @backlog, creator: @user)
        @headers = api_headers_for(@user)
      end

      # Authentication
      test 'returns unauthorized without token' do
        get api_v1_team_issue_comments_path(@team, @issue),
            headers: { 'Content-Type' => 'application/json' }
        assert_response :unauthorized
      end

      # Team scoping
      test 'returns not found for non-member team' do
        other_user = User.create!(name: 'Other', email: 'other_comments@example.com', password: 'password')
        other_workspace = Workspace.create!(name: 'Other WS', owner: other_user)
        other_team = other_workspace.teams.create!(name: 'Other', identifier: 'OTC')
        other_lane = other_team.lanes.create!(name: 'Backlog', position: 0)
        other_issue = other_team.issues.create!(title: 'Other issue', lane: other_lane, creator: other_user)

        get api_v1_team_issue_comments_path(other_team, other_issue), headers: @headers
        assert_response :not_found
      end

      test 'returns not found for issue outside team' do
        get api_v1_team_issue_comments_path(@team, 999_999), headers: @headers
        assert_response :not_found
      end

      # Index
      test 'lists top-level comments with replies nested' do
        parent = @issue.comments.create!(user: @user, body: 'Top level')
        @issue.comments.create!(user: @user, body: 'Reply 1', parent: parent)
        @issue.comments.create!(user: @user, body: 'Another top level')

        get api_v1_team_issue_comments_path(@team, @issue), headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 2, json.length

        first = json.find { |c| c['body'] == 'Top level' }
        assert_equal 1, first['replies'].length
        assert_equal 'Reply 1', first['replies'].first['body']
        assert_equal @user.id, first['user']['id']

        second = json.find { |c| c['body'] == 'Another top level' }
        assert_equal [], second['replies']
      end

      # Create
      test 'creating a comment makes the issue appear in the next updated_since pull' do
        since = 1.minute.ago
        @issue.update_columns(updated_at: 1.hour.ago)

        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: 'Touch' } }.to_json, headers: @headers
        assert_response :created

        get api_v1_team_issues_path(@team, updated_since: since.utc.iso8601(6)), headers: @headers
        assert_response :success
        assert_includes JSON.parse(response.body).map { |i| i['id'] }, @issue.id
      end

      test 'creates comment and sets author from token' do
        assert_difference 'Comment.count', 1 do
          post api_v1_team_issue_comments_path(@team, @issue),
               params: { comment: { body: 'Hello from API' } }.to_json,
               headers: @headers
        end

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'Hello from API', json['body']
        assert_equal @user.id, json['user']['id']
        assert_nil json['parent_id']
      end

      test 'creates reply when parent_id is provided' do
        parent = @issue.comments.create!(user: @user, body: 'Top level')

        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: 'A reply', parent_id: parent.id } }.to_json,
             headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal parent.id, json['parent_id']
      end

      test 'ignores user_id in params and uses token user' do
        other_user = User.create!(name: 'Other', email: 'other_param@example.com', password: 'password')

        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: 'Spoofed', user_id: other_user.id } }.to_json,
             headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal @user.id, json['user']['id']
      end

      test 'returns validation errors for empty body' do
        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: '' } }.to_json,
             headers: @headers

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert json['errors'].present?
      end

      test 'creates a notification for the issue creator on comment' do
        commenter = User.create!(name: 'Commenter', email: 'commenter@example.com', password: 'password')
        @team.team_memberships.create!(user: commenter)
        commenter_headers = api_headers_for(commenter)

        assert_difference 'Notification.where(action: \'commented\').count', 1 do
          post api_v1_team_issue_comments_path(@team, @issue),
               params: { comment: { body: 'Heads up' } }.to_json,
               headers: commenter_headers
        end
      end

      # Scope enforcement
      test 'read-only token cannot create comments' do
        read_only = ApiToken.generate_for(@user, scopes: %w[read])
        headers = { 'Authorization' => "Bearer #{read_only.raw_token}", 'Content-Type' => 'application/json' }

        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: 'nope' } }.to_json,
             headers: headers

        assert_response :forbidden
      end

      # Attachments
      def comment_signed_id(name = 'c.txt')
        ActiveStorage::Blob.create_and_upload!(io: StringIO.new('hi'), filename: name, content_type: 'text/plain')
                           .signed_id
      end

      def create_file_comment(headers: @headers, body: nil)
        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: body }, files: [comment_signed_id] }.to_json, headers: headers
      end

      test 'files-only comment is created and lists files' do
        create_file_comment

        assert_response :created
        assert_equal %w[c.txt], response.parsed_body['files'].pluck('filename')
        get api_v1_team_issue_comments_path(@team, @issue), headers: @headers
        assert_equal %w[c.txt], response.parsed_body.first['files'].pluck('filename')
      end

      test 'invalid file signed id is 422 and creates nothing' do
        assert_no_difference 'Comment.count' do
          post api_v1_team_issue_comments_path(@team, @issue),
               params: { comment: { body: 'x' }, files: ['bogus'] }.to_json, headers: @headers
        end
        assert_response :unprocessable_entity
      end

      test 'author removes comment attachment and issue is touched' do
        create_file_comment
        comment = Comment.find(response.parsed_body['id'])
        att_id = response.parsed_body['files'].first['id']
        @issue.update_columns(updated_at: 1.day.ago)

        delete api_v1_team_issue_comment_attachment_path(@team, @issue, comment, att_id), headers: @headers

        assert_response :no_content
        assert_not comment.reload.files.attached?
        assert_operator @issue.reload.updated_at, :>, 1.minute.ago
      end

      test 'non-author non-admin cannot remove comment attachment' do
        create_file_comment
        comment = Comment.find(response.parsed_body['id'])
        att_id = response.parsed_body['files'].first['id']
        member = User.create!(name: 'Mem', email: 'mem_att@example.com', password: 'password')
        @team.team_memberships.create!(user: member)

        delete api_v1_team_issue_comment_attachment_path(@team, @issue, comment, att_id),
               headers: api_headers_for(member)

        assert_response :forbidden
        assert comment.reload.files.attached?
      end

      test 'team admin can remove another user comment attachment' do
        member = User.create!(name: 'Mem2', email: 'mem2_att@example.com', password: 'password')
        @team.team_memberships.create!(user: member)
        create_file_comment(headers: api_headers_for(member))
        comment = Comment.find(response.parsed_body['id'])
        att_id = response.parsed_body['files'].first['id']
        assert @team.admin?(@user)

        delete api_v1_team_issue_comment_attachment_path(@team, @issue, comment, att_id), headers: @headers

        assert_response :no_content
      end
    end
  end
end
