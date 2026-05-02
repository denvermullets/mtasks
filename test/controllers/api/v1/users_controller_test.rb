require 'test_helper'

module Api
  module V1
    class UsersControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Me User', email: 'me@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Me WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Me Team', identifier: 'METM')
        @team.team_memberships.create!(user: @user)
      end

      def headers_for(token)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      test 'returns the authenticated user and token info' do
        token = ApiToken.generate_for(@user, name: 'CLI Token')

        get api_v1_me_path, headers: headers_for(token)

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal @user.id, json['id']
        assert_equal @user.name, json['name']
        assert_equal @user.email, json['email']
        assert_equal 'CLI Token', json.dig('token', 'name')
        assert_equal %w[read write], json.dig('token', 'scopes')
        assert_nil json.dig('token', 'team_id')
      end

      test 'reports team_id for team-scoped tokens' do
        token = ApiToken.generate_for(@user, name: 'Scoped', team: @team)

        get api_v1_me_path, headers: headers_for(token)

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal @team.id, json.dig('token', 'team_id')
      end

      test 'rejects requests without a valid token' do
        get api_v1_me_path
        assert_response :unauthorized
      end
    end
  end
end
