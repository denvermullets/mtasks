require 'test_helper'

module Api
  module V1
    class TokenAuthTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Auth User', email: 'auth@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Auth WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Auth Team', identifier: 'ATH')
        @team.team_memberships.create!(user: @user)

        @other_workspace = Workspace.create!(name: 'Other WS', owner: @user)
        @other_team = @other_workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
        @other_team.team_memberships.create!(user: @user)
      end

      def headers_for(token)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      test 'unscoped token works across all user teams' do
        token = ApiToken.generate_for(@user, name: 'Wide')

        get api_v1_team_projects_path(@team), headers: headers_for(token)
        assert_response :success

        get api_v1_team_projects_path(@other_team), headers: headers_for(token)
        assert_response :success
      end

      test 'team-scoped token allows requests to its team' do
        token = ApiToken.generate_for(@user, name: 'Scoped', team: @team)

        get api_v1_team_projects_path(@team), headers: headers_for(token)
        assert_response :success
      end

      test 'team-scoped token rejects requests to other teams' do
        token = ApiToken.generate_for(@user, name: 'Scoped', team: @team)

        get api_v1_team_projects_path(@other_team), headers: headers_for(token)
        assert_response :not_found
      end

      test 'read-only token allows GET requests' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])

        get api_v1_team_projects_path(@team), headers: headers_for(token)
        assert_response :success
      end

      test 'read-only token rejects write requests' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])

        post api_v1_team_projects_path(@team),
             params: { project: { name: 'Nope' } }.to_json,
             headers: headers_for(token)
        assert_response :forbidden
        json = JSON.parse(response.body)
        assert_equal 'Forbidden', json['error']
      end

      test 'read+write token allows write requests' do
        token = ApiToken.generate_for(@user, name: 'RW', scopes: %w[read write])

        assert_difference 'Project.count', 1 do
          post api_v1_team_projects_path(@team),
               params: { project: { name: 'Yes', status: 'backlog', priority: 'medium' } }.to_json,
               headers: headers_for(token)
        end
        assert_response :created
      end
    end
  end
end
