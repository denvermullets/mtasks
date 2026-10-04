require 'test_helper'

module HourglassIntegrations
  class DisconnectServiceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: 'Disc User', email: "disc_#{SecureRandom.hex(4)}@example.com", password: 'password')
      @workspace = Workspace.create!(name: 'Disc WS', owner: @user)
      @token = ApiToken.generate_for(@user, name: 'cb')
      @integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv_x', base_url: 'https://hg.test',
        active: true, callback_api_token: @token
      )
    end

    test 'toggles active to false and revokes callback token' do
      DisconnectService.new(@integration).call

      assert_not @integration.reload.active?
      assert @token.reload.revoked?
    end

    test 'deactivates every subscription and breaks the integration links' do
      team = @workspace.teams.create!(name: 'Disc Team', identifier: 'DSC')
      SubscribeTeamsService.call(integration: @integration, teams: [team])
      project = team.projects.create!(name: 'Disc project')
      link = HourglassLink.create!(team: team, link_type: 'project_channel', mtasks_project: project,
                                   hourglass_channel_id: 'ch_disc', hourglass_integration: @integration)

      DisconnectService.new(@integration).call

      assert_empty @integration.active_subscriptions
      assert_predicate link.reload, :broken?
    end

    test 'is safe with no callback token' do
      @integration.update!(callback_api_token: nil)
      DisconnectService.new(@integration).call
      assert_not @integration.reload.active?
    end

    test 'does not double-revoke an already-revoked token' do
      @token.revoke!
      original = @token.revoked_at

      DisconnectService.new(@integration).call

      assert_equal original.to_i, @token.reload.revoked_at.to_i
    end
  end
end
