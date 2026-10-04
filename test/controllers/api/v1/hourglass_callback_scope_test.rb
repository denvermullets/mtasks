require 'test_helper'

module Api
  module V1
    # The Hourglass callback token's reach follows the integration's subscriptions, on the same credential.
    class HourglassCallbackScopeTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'CB User', email: "cbscope_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @workspace = Workspace.create!(name: 'CB WS', owner: @user)
        @team1 = build_team('One', 'CBO')
        @team2 = build_team('Two', 'CBT')
        @token = ApiToken.generate_for(@user, name: 'Hourglass connection', teams: [])
        @integration = @workspace.hourglass_integrations.create!(
          hourglass_server_id: 'srv_x', base_url: 'https://hg.test', active: true, callback_api_token: @token
        )
        @headers = { 'Authorization' => "Bearer #{@token.raw_token}", 'Content-Type' => 'application/json' }
      end

      def build_team(name, identifier)
        team = @workspace.teams.create!(name: name, identifier: identifier)
        team.team_memberships.create!(user: @user)
        team
      end

      test 'removing a team from the server cuts that team off but keeps the token working for the rest' do
        HourglassIntegrations::SubscribeTeamsService.call(integration: @integration, teams: [@team1, @team2])
        get api_v1_team_projects_path(@team1), headers: @headers
        assert_response :success

        HourglassIntegrations::UnsubscribeTeamService.call(integration: @integration, team: @team1)

        get api_v1_team_projects_path(@team1), headers: @headers
        assert_response :not_found
        get api_v1_team_projects_path(@team2), headers: @headers
        assert_response :success
      end
    end
  end
end
