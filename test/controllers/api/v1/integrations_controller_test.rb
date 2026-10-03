require 'test_helper'

module Api
  module V1
    class IntegrationsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'WS Owner', email: "intowner_#{SecureRandom.hex(4)}@example.com",
                             password: 'password')
        @workspace = Workspace.create!(name: 'Int WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Mine', identifier: 'MINE')
        @team.team_memberships.create!(user: @user)
      end

      def bootstrap_headers(token)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      def issue_bootstrap(name: 'bootstrap', scopes: ApiToken::AVAILABLE_SCOPES, teams: [@team])
        ApiTokens::Issuer.call(
          user: @user, workspace: @workspace, name: name, one_time_use: true, scopes: scopes, teams: teams
        )
      end

      def valid_payload
        {
          hourglass_server_id: 'srv_42',
          hourglass_server_name: 'Acme',
          base_url: 'https://hg.example',
          api_token: 'hg_inbound_token'
        }.to_json
      end

      test 'happy path persists integration, mints callback, revokes bootstrap' do
        boot = issue_bootstrap

        post api_v1_integrations_handshake_path,
             params: valid_payload, headers: bootstrap_headers(boot)

        assert_response :created
        json = JSON.parse(response.body)
        assert_predicate json['integration_id'], :present?
        assert_equal @workspace.id, json['workspace_id']
        assert_predicate json['callback_token'], :present?

        integration = HourglassIntegration.find(json['integration_id'])
        assert_equal 'srv_42', integration.hourglass_server_id
        assert_equal 'Acme', integration.hourglass_server_name
        assert_equal 'https://hg.example', integration.base_url
        assert_equal 'hg_inbound_token', integration.api_token
        assert_predicate integration.webhook_secret, :present?
        assert integration.callback_api_token.present?
        assert integration.active?

        assert boot.reload.revoked?
      end

      test 'subscribes only the bootstrap token teams and scopes the callback to them' do
        sibling = @workspace.teams.create!(name: 'Sibling', identifier: 'SIB')
        elsewhere = Workspace.create!(name: 'Elsewhere', owner: @user).teams.create!(name: 'Far', identifier: 'FAR')
        [sibling, elsewhere].each { |t| t.team_memberships.create!(user: @user) }

        post api_v1_integrations_handshake_path,
             params: valid_payload, headers: bootstrap_headers(issue_bootstrap)

        integration = HourglassIntegration.find(JSON.parse(response.body)['integration_id'])
        assert_equal [@team.id], integration.active_subscriptions.pluck(:team_id)
        callback = integration.callback_api_token
        assert callback.team_scoped?
        assert callback.allows_team?(@team)
        assert_not callback.allows_team?(sibling)
        assert_not callback.allows_team?(elsewhere)
        assert_nil callback.workspace_id
      end

      test 'unscoped bootstrap token is rejected without connecting anything' do
        boot = issue_bootstrap(teams: nil)

        assert_no_difference -> { HourglassIntegration.count } do
          post api_v1_integrations_handshake_path, params: valid_payload, headers: bootstrap_headers(boot)
        end
        assert_response :unprocessable_entity
        assert_not boot.reload.revoked?
      end

      test 'bootstrap token scoped only to teams outside its workspace is rejected' do
        far = Workspace.create!(name: 'Elsewhere', owner: @user).teams.create!(name: 'Far', identifier: 'FAR')
        far.team_memberships.create!(user: @user)

        post api_v1_integrations_handshake_path,
             params: valid_payload, headers: bootstrap_headers(issue_bootstrap(teams: [far]))
        assert_response :unprocessable_entity
      end

      test 'replay with revoked bootstrap returns 401' do
        boot = issue_bootstrap

        post api_v1_integrations_handshake_path,
             params: valid_payload, headers: bootstrap_headers(boot)
        assert_response :created

        post api_v1_integrations_handshake_path,
             params: valid_payload, headers: bootstrap_headers(boot)
        assert_response :unauthorized
      end

      test 'non-bootstrap token (no one_time_use) returns 403' do
        regular = ApiToken.generate_for(@user, name: 'regular')
        post api_v1_integrations_handshake_path,
             params: valid_payload, headers: bootstrap_headers(regular)
        assert_response :forbidden
      end

      test 'read-only scope returns 403 on POST' do
        boot = issue_bootstrap(name: 'ro', scopes: %w[read])
        post api_v1_integrations_handshake_path,
             params: valid_payload, headers: bootstrap_headers(boot)
        assert_response :forbidden
      end

      test 'second handshake for same workspace+server updates integration in place' do
        post api_v1_integrations_handshake_path, params: valid_payload, headers: bootstrap_headers(issue_bootstrap)
        first_id = JSON.parse(response.body)['integration_id']

        post api_v1_integrations_handshake_path,
             params: { hourglass_server_id: 'srv_42', hourglass_server_name: 'Renamed',
                       base_url: 'https://hg.example', api_token: 'updated' }.to_json,
             headers: bootstrap_headers(issue_bootstrap)

        assert_response :created
        second_id = JSON.parse(response.body)['integration_id']
        assert_equal first_id, second_id

        integration = HourglassIntegration.find(first_id)
        assert_equal 'updated', integration.api_token
        assert_equal 'Renamed', integration.hourglass_server_name
      end

      test 'second handshake rotates the callback token and keeps every subscribed team in scope' do
        other = @workspace.teams.create!(name: 'Other', identifier: 'OTH')
        other.team_memberships.create!(user: @user)

        post api_v1_integrations_handshake_path, params: valid_payload, headers: bootstrap_headers(issue_bootstrap)
        integration = HourglassIntegration.find(JSON.parse(response.body)['integration_id'])
        first_callback = integration.callback_api_token

        post api_v1_integrations_handshake_path, params: valid_payload,
                                                 headers: bootstrap_headers(issue_bootstrap(teams: [other]))
        assert_response :created

        integration.reload
        assert first_callback.reload.revoked?
        assert_equal [@team.id, other.id].sort, integration.callback_api_token.scoped_team_ids.sort
        assert_equal [@team.id, other.id].sort, integration.active_subscriptions.pluck(:team_id).sort
      end

      test 'missing required field returns parameter error' do
        post api_v1_integrations_handshake_path,
             params: { hourglass_server_id: 'srv_42' }.to_json,
             headers: bootstrap_headers(issue_bootstrap)
        assert_response :bad_request
      end
    end
  end
end
