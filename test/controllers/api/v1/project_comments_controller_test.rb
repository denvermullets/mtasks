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
