require 'test_helper'
require 'webmock/minitest'

module Settings
  class HourglassIntegrationsControllerTest < ActionDispatch::IntegrationTest
    BASE = 'https://hg.test'.freeze

    setup do
      WebMock.disable_net_connect!
      @user = User.create!(name: 'WS Owner', email: "wsadm_#{SecureRandom.hex(4)}@example.com", password: 'password')
      @workspace = Workspace.create!(name: 'Owner WS', owner: @user)
      @team = @workspace.teams.create!(name: 'T1', identifier: 'TT1')
      @team.team_memberships.create!(user: @user)
      sign_in_as(@user)
    end

    teardown do
      WebMock.reset!
      WebMock.allow_net_connect!
    end

    test 'show renders connect form when not connected' do
      get workspace_settings_hourglass_integration_path(@workspace)
      assert_response :success
      assert_includes response.body, 'Connect Hourglass'
    end

    test 'update connects on valid token' do
      stub_request(:get, "#{BASE}/api/v1/me")
        .to_return(status: 200, body: { server: { id: 'srv_1', name: 'Acme' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "#{BASE}/api/v1/servers/srv_1/channels")
        .to_return(status: 200, body: [{ id: 1 }, { id: 2 }].to_json,
                   headers: { 'Content-Type' => 'application/json' })

      patch workspace_settings_hourglass_integration_path(@workspace),
            params: { base_url: BASE, api_token: 'tk_ok' }

      assert_redirected_to workspace_settings_hourglass_integration_path(@workspace)
      assert_equal 'Connected to Acme · 2 channels', flash[:notice]
      assert @workspace.hourglass_integrations.active.exists?
    end

    test 'update with bad token shows friendly alert' do
      stub_request(:get, "#{BASE}/api/v1/me").to_return(status: 401, body: '{}')

      patch workspace_settings_hourglass_integration_path(@workspace),
            params: { base_url: BASE, api_token: 'bad' }

      assert_redirected_to workspace_settings_hourglass_integration_path(@workspace)
      assert_equal 'Invalid hourglass token', flash[:alert]
      assert_not @workspace.hourglass_integrations.exists?
    end

    test 'destroy disconnects existing integration' do
      token = ApiToken.generate_for(@user, name: 'cb')
      @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv_x', base_url: BASE,
        active: true, callback_api_token: token
      )

      delete workspace_settings_hourglass_integration_path(@workspace)

      assert_redirected_to workspace_settings_hourglass_integration_path(@workspace)
      assert_equal 'Hourglass disconnected', flash[:notice]
      assert_not @workspace.hourglass_integrations.first.active?
      assert token.reload.revoked?
    end

    test 'denies non-workspace member' do
      outsider = User.create!(name: 'Outsider', email: "out_#{SecureRandom.hex(4)}@example.com", password: 'password')
      sign_out
      sign_in_as(outsider)

      get workspace_settings_hourglass_integration_path(@workspace)
      assert_redirected_to root_path
      assert_equal 'Access denied', flash[:alert]
    end
  end
end
