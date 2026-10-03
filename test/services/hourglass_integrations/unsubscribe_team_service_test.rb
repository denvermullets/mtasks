require 'test_helper'

module HourglassIntegrations
  class UnsubscribeTeamServiceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: 'Unsub User', email: "unsub_#{SecureRandom.hex(4)}@example.com", password: 'password')
      @workspace = Workspace.create!(name: 'Unsub WS', owner: @user)
      @team_a = @workspace.teams.create!(name: 'Alpha', identifier: 'UNA')
      @team_b = @workspace.teams.create!(name: 'Beta', identifier: 'UNB')
      @token = ApiToken.generate_for(@user, name: 'cb', teams: [])
      @integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv_x', base_url: 'https://hg.test', active: true, callback_api_token: @token
      )
      SubscribeTeamsService.call(integration: @integration, teams: [@team_a, @team_b])
    end

    def link_for(team, channel_id)
      project = team.projects.create!(name: "#{team.name} project")
      HourglassLink.create!(team: team, link_type: 'project_channel', mtasks_project: project,
                            hourglass_channel_id: channel_id, hourglass_integration: @integration)
    end

    test 'narrows the token, deactivates the subscription and breaks only that team links' do
      link_a = link_for(@team_a, 'ch_a')
      link_b = link_for(@team_b, 'ch_b')

      UnsubscribeTeamService.call(integration: @integration, team: @team_a)

      assert_equal [@team_b.id], @token.reload.scoped_team_ids
      assert_not @token.allows_team?(@team_a)
      assert @token.allows_team?(@team_b)
      assert_equal [@team_b.id], @integration.active_subscriptions.pluck(:team_id)
      assert_predicate link_a.reload, :broken?
      assert_predicate link_b.reload, :active?
      assert @integration.reload.active?
      assert_not @token.revoked?
    end

    test 'removing the last team disconnects the integration and revokes the token' do
      UnsubscribeTeamService.call(integration: @integration, team: @team_a)
      UnsubscribeTeamService.call(integration: @integration, team: @team_b)

      assert_not @integration.reload.active?
      assert @token.reload.revoked?
      assert_empty @integration.active_subscriptions
    end

    test 'is a no-op for a team that is not subscribed' do
      other = @workspace.teams.create!(name: 'Other', identifier: 'UNO')

      UnsubscribeTeamService.call(integration: @integration, team: other)

      assert_equal [@team_a.id, @team_b.id].sort, @token.reload.scoped_team_ids.sort
    end

    test 'subscriptions refuse teams outside the integration workspace' do
      far = Workspace.create!(name: 'Far', owner: @user).teams.create!(name: 'Far', identifier: 'UNF')

      assert_raises(ActiveRecord::RecordInvalid) do
        SubscribeTeamsService.call(integration: @integration, teams: [far])
      end
      assert_equal [@team_a.id, @team_b.id].sort, @token.reload.scoped_team_ids.sort
    end
  end
end
