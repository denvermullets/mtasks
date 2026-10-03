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

      other = @workspace.teams.create!(name: 'T2', identifier: 'TT2')

      patch workspace_settings_hourglass_integration_path(@workspace),
            params: { base_url: BASE, api_token: 'tk_ok', team_ids: [@team.id] }

      assert_redirected_to workspace_settings_hourglass_integration_path(@workspace)
      assert_equal 'Connected T1 to Acme · 2 channels', flash[:notice]
      integration = @workspace.hourglass_integrations.active.sole
      assert_equal [@team.id], integration.active_subscriptions.pluck(:team_id)
      assert_not_includes integration.callback_api_token.scoped_team_ids, other.id
    end

    test 'update without any team connects nothing' do
      patch workspace_settings_hourglass_integration_path(@workspace),
            params: { base_url: BASE, api_token: 'tk_ok' }

      assert_equal 'Pick at least one team to connect', flash[:alert]
      assert_not @workspace.hourglass_integrations.exists?
    end

    test 'update ignores teams the user does not manage' do
      owner = User.create!(name: 'Other Owner', email: "oo_#{SecureRandom.hex(4)}@example.com", password: 'password')
      foreign = Workspace.create!(name: 'Foreign', owner: owner).teams.create!(name: 'F', identifier: 'FFF')

      patch workspace_settings_hourglass_integration_path(@workspace),
            params: { base_url: BASE, api_token: 'tk_ok', team_ids: [foreign.id] }

      assert_equal 'Pick at least one team to connect', flash[:alert]
    end

    test 'update with bad token shows friendly alert' do
      stub_request(:get, "#{BASE}/api/v1/me").to_return(status: 401, body: '{}')

      patch workspace_settings_hourglass_integration_path(@workspace),
            params: { base_url: BASE, api_token: 'bad', team_ids: [@team.id] }

      assert_redirected_to workspace_settings_hourglass_integration_path(@workspace)
      assert_equal 'Invalid hourglass token', flash[:alert]
      assert_not @workspace.hourglass_integrations.exists?
    end

    def create_integration(teams: [@team])
      token = ApiToken.generate_for(@user, name: 'cb', teams: [])
      integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv_x', hourglass_server_name: 'Acme', base_url: BASE,
        active: true, callback_api_token: token
      )
      HourglassIntegrations::SubscribeTeamsService.call(integration: integration, teams: teams)
      integration
    end

    test 'destroy disconnects existing integration' do
      integration = create_integration

      delete workspace_settings_hourglass_integration_path(@workspace, integration_id: integration.id)

      assert_redirected_to workspace_settings_hourglass_integration_path(@workspace)
      assert_equal 'Hourglass disconnected', flash[:notice]
      assert_not integration.reload.active?
      assert integration.callback_api_token.reload.revoked?
    end

    test 'destroy without an integration id does not guess one' do
      integration = create_integration

      delete workspace_settings_hourglass_integration_path(@workspace)

      assert_equal 'No active Hourglass connection', flash[:alert]
      assert integration.reload.active?
    end

    test 'add_team and remove_team keep subscriptions and token scope in step' do
      other = @workspace.teams.create!(name: 'T2', identifier: 'TT2')
      integration = create_integration

      post add_team_workspace_settings_hourglass_integration_path(@workspace),
           params: { integration_id: integration.id, team_id: other.id }
      assert_equal 'T2 now uses Acme', flash[:notice]
      assert_equal [@team.id, other.id].sort, integration.callback_api_token.reload.scoped_team_ids.sort

      delete remove_team_workspace_settings_hourglass_integration_path(@workspace),
             params: { integration_id: integration.id, team_id: @team.id }
      assert_equal 'T1 removed from Acme', flash[:notice]
      assert_equal [other.id], integration.callback_api_token.reload.scoped_team_ids
      assert integration.reload.active?
    end

    test 'members can only manage their own teams and cannot disconnect a server shared with others' do
      member = User.create!(name: 'Member', email: "mem_#{SecureRandom.hex(4)}@example.com", password: 'password')
      mine = @workspace.teams.create!(name: 'Mine', identifier: 'MIN')
      mine.team_memberships.create!(user: member)
      integration = create_integration(teams: [@team, mine])
      sign_out
      sign_in_as(member)

      delete remove_team_workspace_settings_hourglass_integration_path(@workspace),
             params: { integration_id: integration.id, team_id: @team.id }
      assert_equal 'Team not found', flash[:alert]

      delete workspace_settings_hourglass_integration_path(@workspace, integration_id: integration.id)
      assert_match(/manages every connected team/, flash[:alert])
      assert integration.reload.active?

      delete remove_team_workspace_settings_hourglass_integration_path(@workspace),
             params: { integration_id: integration.id, team_id: mine.id }
      assert_equal [@team.id], integration.active_subscriptions.pluck(:team_id)
    end

    test 'show lists the teams using each server' do
      create_integration

      get workspace_settings_hourglass_integration_path(@workspace)

      assert_response :success
      assert_includes response.body, 'Teams using this server'
      assert_includes response.body, 'Remove'
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
