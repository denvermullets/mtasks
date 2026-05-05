require 'test_helper'
require 'webmock/minitest'

module HourglassIntegrations
  class ConnectServiceTest < ActiveSupport::TestCase
    BASE = 'https://hg.test'.freeze

    def setup
      WebMock.disable_net_connect!
      @user = User.create!(name: 'Conn User', email: "conn_#{SecureRandom.hex(4)}@example.com", password: 'password')
      @workspace = Workspace.create!(name: 'Conn WS', owner: @user)
      @team_a = Team.create!(name: 'Alpha', identifier: 'AAA', workspace: @workspace)
      @team_b = Team.create!(name: 'Beta', identifier: 'BBB', workspace: @workspace)
    end

    def teardown
      WebMock.reset!
      WebMock.allow_net_connect!
    end

    def stub_me(status: 200, body: { id: 1, email: 'a@b', server: { id: 'srv_1', name: 'Acme' } })
      stub_request(:get, "#{BASE}/api/v1/me")
        .to_return(status: status, body: body.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    def stub_channels(server_id: 'srv_1', count: 3)
      stub_request(:get, "#{BASE}/api/v1/servers/#{server_id}/channels")
        .to_return(status: 200, body: Array.new(count) { |i| { id: i + 1 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    test 'happy path persists integration, mints callback token, fans out subscriptions' do
      stub_me
      stub_channels(count: 3)

      result = run_connect(api_token: 'tk_good')
      integration = result.integration

      assert_equal 3, result.channel_count
      assert_integration_persisted(integration, api_token: 'tk_good',
                                                server_id: 'srv_1', server_name: 'Acme')
      assert_subscriptions_for_each_team(integration)
    end

    test 'persists hourglass_integration_id from /me integration field' do
      stub_me(body: { id: 1, email: 'a@b', server: { id: 'srv_1', name: 'Acme' },
                      integration: { id: 99 } })
      stub_channels(count: 0)

      result = run_connect(api_token: 'tk_good')
      assert_equal 99, result.integration.hourglass_integration_id
    end

    test 'adopts webhook_secret from /me when Hourglass exposes one' do
      stub_me(body: { id: 1, email: 'a@b', server: { id: 'srv_1', name: 'Acme' },
                      integration: { id: 99, webhook_secret: 'shared-secret-xyz' } })
      stub_channels(count: 0)

      result = run_connect(api_token: 'tk_good')
      assert_equal 'shared-secret-xyz', result.integration.webhook_secret
    end

    test 'falls back to a locally generated webhook_secret when /me lacks one' do
      stub_me(body: { id: 1, email: 'a@b', server: { id: 'srv_1', name: 'Acme' },
                      integration: { id: 99 } })
      stub_channels(count: 0)

      result = run_connect(api_token: 'tk_good')
      assert_predicate result.integration.webhook_secret, :present?
    end

    test 'raises Error when /me does not return a server' do
      stub_me(body: { id: 1, email: 'a@b' })

      assert_no_difference -> { HourglassIntegration.count } do
        assert_raises(Hourglass::ApiClient::Error) do
          run_connect(api_token: 'tk_good')
        end
      end
    end

    def run_connect(api_token:)
      ConnectService.new(
        workspace: @workspace, current_user: @user,
        base_url: BASE, api_token: api_token
      ).call
    end

    def assert_integration_persisted(integration, api_token:, server_id:, server_name:)
      assert_equal server_id, integration.hourglass_server_id
      assert_equal server_name, integration.hourglass_server_name
      assert_equal BASE, integration.base_url
      assert_equal api_token, integration.api_token
      assert_predicate integration.webhook_secret, :present?
      assert_equal @user, integration.connected_by_user
      assert_equal @user, integration.callback_api_token.user
      assert integration.active?
      assert_not integration.callback_api_token.revoked?
    end

    def assert_subscriptions_for_each_team(integration)
      subs = integration.hourglass_channel_subscriptions
      assert_equal [@team_a.id, @team_b.id].sort, subs.pluck(:team_id).sort
      assert subs.all?(&:active?)
    end

    test 'bad token: raises Unauthorized, no DB writes' do
      stub_me(status: 401)

      assert_no_difference -> { HourglassIntegration.count } do
        assert_no_difference -> { ApiToken.count } do
          assert_raises(Hourglass::ApiClient::Unauthorized) do
            ConnectService.new(workspace: @workspace, current_user: @user,
                               base_url: BASE, api_token: 'bad').call
          end
        end
      end
    end

    test 'discover failure rolls back: no integration row persisted' do
      stub_me
      stub_request(:get, "#{BASE}/api/v1/servers/srv_1/channels").to_return(status: 500, body: '{}')

      assert_no_difference -> { HourglassIntegration.count } do
        assert_no_difference -> { HourglassChannelSubscription.count } do
          assert_raises(Hourglass::ApiClient::Error) do
            ConnectService.new(workspace: @workspace, current_user: @user,
                               base_url: BASE, api_token: 'tk').call
          end
        end
      end

      token = ApiToken.where(user: @user).order(:id).last
      assert token.revoked?
    end

    test 'discover 404 is best-effort: integration persists with zero channels' do
      stub_me
      stub_request(:get, "#{BASE}/api/v1/servers/srv_1/channels").to_return(status: 404, body: '{}')

      result = ConnectService.new(workspace: @workspace, current_user: @user,
                                  base_url: BASE, api_token: 'tk').call

      assert_equal 0, result.channel_count
      assert result.integration.persisted?
      assert_not result.integration.callback_api_token.revoked?
    end

    test 'reconnect updates existing integration in place' do
      stub_me
      stub_channels(count: 3)

      ConnectService.new(workspace: @workspace, current_user: @user,
                         base_url: BASE, api_token: 'tk1').call
      first_id = HourglassIntegration.last.id

      stub_channels(count: 5) # different channel count, same server

      assert_no_difference -> { HourglassIntegration.count } do
        ConnectService.new(workspace: @workspace, current_user: @user,
                           base_url: BASE, api_token: 'tk2').call
      end

      reloaded = HourglassIntegration.find(first_id)
      assert_equal 'tk2', reloaded.api_token
    end
  end
end
