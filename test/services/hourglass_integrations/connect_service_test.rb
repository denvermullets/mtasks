require 'test_helper'
require 'webmock/minitest'

module HourglassIntegrations
  class ConnectServiceTest < ActiveSupport::TestCase
    BASE = 'https://hg.test'.freeze
    OTHER_BASE = 'https://hg-other.test'.freeze

    def setup
      WebMock.disable_net_connect!
      @user = User.create!(name: 'Conn User', email: "conn_#{SecureRandom.hex(4)}@example.com", password: 'password')
      @workspace = Workspace.create!(name: 'Conn WS', owner: @user)
      @team_a = Team.create!(name: 'Alpha', identifier: 'AAA', workspace: @workspace)
      @team_b = Team.create!(name: 'Beta', identifier: 'BBB', workspace: @workspace)
      @team_c = Team.create!(name: 'Gamma', identifier: 'CCC', workspace: @workspace)
    end

    def teardown
      WebMock.reset!
      WebMock.allow_net_connect!
    end

    def stub_me(status: 200, base: BASE, body: { id: 1, email: 'a@b', server: { id: 'srv_1', name: 'Acme' } })
      stub_request(:get, "#{base}/api/v1/me")
        .to_return(status: status, body: body.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    def stub_channels(server_id: 'srv_1', count: 3, base: BASE)
      stub_request(:get, "#{base}/api/v1/servers/#{server_id}/channels")
        .to_return(status: 200, body: Array.new(count) { |i| { id: i + 1 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    def run_connect(api_token: 'tk_good', teams: [@team_a], base_url: BASE, replace_credentials: false)
      ConnectService.new(
        workspace: @workspace, current_user: @user,
        base_url: base_url, api_token: api_token, teams: teams, replace_credentials: replace_credentials
      ).call
    end

    test 'happy path persists integration, mints callback token, subscribes only the chosen team' do
      stub_me
      stub_channels(count: 3)

      result = run_connect(api_token: 'tk_good')
      integration = result.integration

      assert_equal 3, result.channel_count
      assert_not result.reused
      assert_predicate result.new_callback_token, :present?
      assert_integration_persisted(integration, api_token: 'tk_good',
                                                server_id: 'srv_1', server_name: 'Acme')
      assert_equal [@team_a.id], integration.hourglass_channel_subscriptions.pluck(:team_id)
      assert_equal [@team_a.id], integration.callback_api_token.scoped_team_ids
    end

    test 'connecting a second team to the same server reuses the integration and widens the token' do
      stub_me
      stub_channels
      first = run_connect(teams: [@team_a])

      second = nil
      assert_no_difference -> { HourglassIntegration.count } do
        assert_no_difference -> { ApiToken.count } do
          second = run_connect(api_token: 'tk_other', teams: [@team_b])
        end
      end

      integration = second.integration.reload
      assert_equal first.integration.id, integration.id
      assert second.reused
      assert_nil second.new_callback_token
      assert_equal [@team_a.id, @team_b.id].sort, integration.active_subscriptions.pluck(:team_id).sort
      assert_equal [@team_a.id, @team_b.id].sort, integration.callback_api_token.scoped_team_ids.sort
      assert_not_includes integration.hourglass_channel_subscriptions.pluck(:team_id), @team_c.id
    end

    test 'reuse keeps stored credentials unless replacement is confirmed' do
      stub_me(body: { server: { id: 'srv_1', name: 'Acme' }, integration: { id: 9, webhook_secret: 's1' } })
      stub_channels
      integration = run_connect(api_token: 'tk1').integration

      stub_me(body: { server: { id: 'srv_1', name: 'Acme' }, integration: { id: 9, webhook_secret: 's2' } })
      run_connect(api_token: 'tk2', teams: [@team_b])
      integration.reload
      assert_equal 'tk1', integration.api_token
      assert_equal 's1', integration.webhook_secret

      run_connect(api_token: 'tk3', teams: [@team_b], replace_credentials: true)
      integration.reload
      assert_equal 'tk3', integration.api_token
      assert_equal 's2', integration.webhook_secret
    end

    test 'a different server gets its own integration and token scoped to its team' do
      stub_me
      stub_channels
      x = run_connect(teams: [@team_a, @team_b]).integration

      stub_me(base: OTHER_BASE, body: { server: { id: 'srv_2', name: 'Other' } })
      stub_channels(server_id: 'srv_2', base: OTHER_BASE)
      y = run_connect(teams: [@team_c], base_url: OTHER_BASE).integration

      assert_not_equal x.id, y.id
      assert_not_equal x.callback_api_token_id, y.callback_api_token_id
      assert_equal [@team_c.id], y.callback_api_token.scoped_team_ids
      assert_equal [@team_a.id, @team_b.id].sort, x.reload.callback_api_token.scoped_team_ids.sort
    end

    test 'reconnecting a disconnected server mints a fresh token and only revives the chosen teams' do
      stub_me
      stub_channels
      integration = run_connect(teams: [@team_a, @team_b]).integration
      old_token = integration.callback_api_token
      DisconnectService.call(integration)

      result = run_connect(api_token: 'tk2', teams: [@team_b])

      integration.reload
      assert integration.active?
      assert_not result.reused
      assert_equal 'tk2', integration.api_token
      assert old_token.reload.revoked?
      assert_equal [@team_b.id], integration.active_subscriptions.pluck(:team_id)
      assert_equal [@team_b.id], integration.callback_api_token.scoped_team_ids
    end

    test 'refuses teams from another workspace and an empty team list' do
      far = Team.create!(name: 'Far', identifier: 'FAR', workspace: Workspace.create!(name: 'Far WS', owner: @user))

      assert_raises(ArgumentError) { run_connect(teams: [far]) }
      assert_raises(ArgumentError) { run_connect(teams: []) }
    end

    test 'persists hourglass_integration_id from /me integration field' do
      stub_me(body: { id: 1, email: 'a@b', server: { id: 'srv_1', name: 'Acme' },
                      integration: { id: 99 } })
      stub_channels(count: 0)

      assert_equal 99, run_connect.integration.hourglass_integration_id
    end

    test 'adopts webhook_secret from /me when Hourglass exposes one' do
      stub_me(body: { id: 1, email: 'a@b', server: { id: 'srv_1', name: 'Acme' },
                      integration: { id: 99, webhook_secret: 'shared-secret-xyz' } })
      stub_channels(count: 0)

      assert_equal 'shared-secret-xyz', run_connect.integration.webhook_secret
    end

    test 'falls back to a locally generated webhook_secret when /me lacks one' do
      stub_me(body: { id: 1, email: 'a@b', server: { id: 'srv_1', name: 'Acme' },
                      integration: { id: 99 } })
      stub_channels(count: 0)

      assert_predicate run_connect.integration.webhook_secret, :present?
    end

    test 'raises Error when /me does not return a server' do
      stub_me(body: { id: 1, email: 'a@b' })

      assert_no_difference -> { HourglassIntegration.count } do
        assert_raises(Hourglass::ApiClient::Error) { run_connect }
      end
    end

    test 'bad token: raises Unauthorized, no DB writes' do
      stub_me(status: 401)

      assert_no_difference -> { HourglassIntegration.count } do
        assert_no_difference -> { ApiToken.count } do
          assert_raises(Hourglass::ApiClient::Unauthorized) { run_connect(api_token: 'bad') }
        end
      end
    end

    test 'discover failure rolls back: no integration row persisted' do
      stub_me
      stub_request(:get, "#{BASE}/api/v1/servers/srv_1/channels").to_return(status: 500, body: '{}')

      assert_no_difference -> { HourglassIntegration.count } do
        assert_no_difference -> { HourglassChannelSubscription.count } do
          assert_raises(Hourglass::ApiClient::Error) { run_connect(api_token: 'tk') }
        end
      end

      token = ApiToken.where(user: @user).order(:id).last
      assert token.revoked?
    end

    test 'discover 404 is best-effort: integration persists with zero channels' do
      stub_me
      stub_request(:get, "#{BASE}/api/v1/servers/srv_1/channels").to_return(status: 404, body: '{}')

      result = run_connect(api_token: 'tk')

      assert_equal 0, result.channel_count
      assert result.integration.persisted?
      assert_not result.integration.callback_api_token.revoked?
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
  end
end
