require 'test_helper'

module Api
  module V1
    class IntegrationsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'WS Owner', email: "intowner_#{SecureRandom.hex(4)}@example.com",
                             password: 'password')
        @workspace = Workspace.create!(name: 'Int WS', owner: @user)
      end

      def bootstrap_headers(token)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      def issue_bootstrap(name: 'bootstrap', scopes: ApiToken::AVAILABLE_SCOPES)
        ApiTokens::Issuer.workspace_token(
          user: @user, workspace: @workspace, name: name, one_time_use: true, scopes: scopes
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

      test 'missing required field returns parameter error' do
        post api_v1_integrations_handshake_path,
             params: { hourglass_server_id: 'srv_42' }.to_json,
             headers: bootstrap_headers(issue_bootstrap)
        assert_response :bad_request
      end
    end
  end
end
