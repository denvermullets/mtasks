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

      # by_email
      test 'by_email returns a user who shares a team with caller' do
        teammate = User.create!(name: 'Mate', email: 'mate@example.com', password: 'password')
        @team.team_memberships.create!(user: teammate)

        token = ApiToken.generate_for(@user, name: 't')
        get api_v1_users_by_email_path(email: 'mate@example.com'), headers: headers_for(token)

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal teammate.id, json['id']
        assert_equal 'mate@example.com', json['email']
      end

      test 'by_email is case-insensitive' do
        teammate = User.create!(name: 'Mate', email: 'mate2@example.com', password: 'password')
        @team.team_memberships.create!(user: teammate)

        token = ApiToken.generate_for(@user, name: 't')
        get api_v1_users_by_email_path(email: 'MATE2@example.COM'), headers: headers_for(token)

        assert_response :success
      end

      test 'by_email returns 404 when user shares no team with caller' do
        outsider = User.create!(name: 'Out', email: 'out@example.com', password: 'password')
        Workspace.create!(name: 'Other', owner: outsider)

        token = ApiToken.generate_for(@user, name: 't')
        get api_v1_users_by_email_path(email: 'out@example.com'), headers: headers_for(token)

        assert_response :not_found
      end

      test 'by_email returns 400 with blank email' do
        token = ApiToken.generate_for(@user, name: 't')
        get api_v1_users_by_email_path, headers: headers_for(token)
        assert_response :bad_request
      end

      test 'by_email rejects without a token' do
        get api_v1_users_by_email_path(email: 'me@example.com')
        assert_response :unauthorized
      end
    end
  end
end
