require 'test_helper'

module Api
  module V1
    class ProjectCommentsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API PC', email: 'api_pc@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'APC')
        @team.team_memberships.create!(user: @user)
        @project = @team.projects.create!(name: 'Proj')
      end

      test 'index returns project comments' do
        @project.comments.create!(user: @user, body: 'first')
        @project.comments.create!(user: @user, body: 'second')

        get api_v1_team_project_comments_path(@team, @project), headers: api_headers_for(@user)

        assert_response :success
        body = JSON.parse(response.body)
        bodies = body.map { |c| c['body'] }
        assert_includes bodies, 'first'
        assert_includes bodies, 'second'
      end

      test 'create persists a comment scoped to the project' do
        assert_difference -> { @project.comments.count }, 1 do
          post api_v1_team_project_comments_path(@team, @project),
               params: { comment: { body: 'from the API' } }.to_json,
               headers: api_headers_for(@user)
        end

        assert_response :created
        comment = @project.comments.last
        assert_equal 'from the API', comment.body
        assert_equal @user.id, comment.user_id
        assert_nil comment.issue_id
      end

      test 'create returns 422 for blank body' do
        post api_v1_team_project_comments_path(@team, @project),
             params: { comment: { body: '' } }.to_json,
             headers: api_headers_for(@user)

        assert_response :unprocessable_entity
      end

      def comment_signed_id(name = 'c.txt')
        ActiveStorage::Blob.create_and_upload!(io: StringIO.new('hi'), filename: name, content_type: 'text/plain')
                           .signed_id
      end

      def create_file_comment(headers: api_headers_for(@user), body: nil)
        post api_v1_team_project_comments_path(@team, @project),
             params: { comment: { body: body }, files: [comment_signed_id] }.to_json, headers: headers
      end

      test 'files-only comment is created, lists files and touches the project' do
        @project.update_columns(updated_at: 1.day.ago)

        create_file_comment

        assert_response :created
        assert_equal %w[c.txt], response.parsed_body['files'].pluck('filename')
        assert_operator @project.reload.updated_at, :>, 1.minute.ago
        get api_v1_team_project_comments_path(@team, @project), headers: api_headers_for(@user)
        assert_equal %w[c.txt], response.parsed_body.first['files'].pluck('filename')
      end

      test 'invalid file signed id is 422 and creates nothing' do
        assert_no_difference 'Comment.count' do
          post api_v1_team_project_comments_path(@team, @project),
               params: { comment: { body: 'x' }, files: ['bogus'] }.to_json, headers: api_headers_for(@user)
        end
        assert_response :unprocessable_entity
      end

      test 'comment attachment is downloadable through the attachment endpoint' do
        create_file_comment

        get api_v1_attachment_download_path(response.parsed_body['files'].first['id']),
            headers: api_headers_for(@user)

        assert_response :redirect
      end

      test 'author removes comment attachment and project is touched' do
        create_file_comment
        comment = Comment.find(response.parsed_body['id'])
        att_id = response.parsed_body['files'].first['id']
        @project.update_columns(updated_at: 1.day.ago)

        delete api_v1_team_project_comment_attachment_path(@team, @project, comment, att_id),
               headers: api_headers_for(@user)

        assert_response :no_content
        assert_not comment.reload.files.attached?
        assert_operator @project.reload.updated_at, :>, 1.minute.ago

        get api_v1_team_projects_path(@team), params: { updated_since: 1.minute.ago.utc.iso8601 },
                                              headers: api_headers_for(@user)
        assert_includes response.parsed_body.pluck('id'), @project.id
      end

      test 'non-author non-admin cannot remove comment attachment' do
        create_file_comment
        comment = Comment.find(response.parsed_body['id'])
        att_id = response.parsed_body['files'].first['id']
        member = User.create!(name: 'Mem', email: 'pc_mem@example.com', password: 'password')
        @team.team_memberships.create!(user: member)

        delete api_v1_team_project_comment_attachment_path(@team, @project, comment, att_id),
               headers: api_headers_for(member)

        assert_response :forbidden
        assert comment.reload.files.attached?
      end

      test 'team admin can remove another user comment attachment' do
        member = User.create!(name: 'Mem2', email: 'pc_mem2@example.com', password: 'password')
        @team.team_memberships.create!(user: member)
        @team.team_memberships.find_by(user: @user).update!(role: 'admin')
        create_file_comment(headers: api_headers_for(member))
        comment = Comment.find(response.parsed_body['id'])
        att_id = response.parsed_body['files'].first['id']

        delete api_v1_team_project_comment_attachment_path(@team, @project, comment, att_id),
               headers: api_headers_for(@user)

        assert_response :no_content
      end

      test 'returns 404 when project not in team' do
        other_team = @workspace.teams.create!(name: 'O', identifier: 'OTH')
        other_project = other_team.projects.create!(name: 'X')

        post api_v1_team_project_comments_path(@team, other_project),
             params: { comment: { body: 'nope' } }.to_json,
             headers: api_headers_for(@user)

        assert_response :not_found
      end
    end
  end
end
