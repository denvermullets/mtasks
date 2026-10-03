require 'test_helper'
require Rails.root.join('db/migrate/20261003130000_narrow_hourglass_subscriptions_to_linked_teams')

class NarrowHourglassSubscriptionsToLinkedTeamsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Mig User', email: "mig_#{SecureRandom.hex(4)}@example.com", password: 'password')
    @workspace = Workspace.create!(name: 'Mig WS', owner: @user)
    @linked = @workspace.teams.create!(name: 'Linked', identifier: 'MGL')
    @legacy = @workspace.teams.create!(name: 'Legacy', identifier: 'MGG')
    @idle = @workspace.teams.create!(name: 'Idle', identifier: 'MGI')
    @token = ApiToken.generate_for(@user, name: 'cb', teams: @workspace.teams)
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv_m', base_url: 'https://hg.test', active: true, callback_api_token: @token
    )
    # The old fan-out: every team subscribed except @legacy, which only has a pre-integration-id link.
    [@linked, @idle].each do |team|
      @integration.hourglass_channel_subscriptions.create!(team: team, hourglass_server_id: 'srv_m', active: true)
    end
    link(@linked, 'ch_1', integration: @integration)
    link(@legacy, 'ch_2', integration: nil)
  end

  def link(team, channel_id, integration:)
    project = team.projects.create!(name: "#{team.name} #{channel_id}")
    HourglassLink.create!(team: team, link_type: 'project_channel', mtasks_project: project,
                          hourglass_channel_id: channel_id, hourglass_integration: integration)
  end

  def migrate!
    ActiveRecord::Migration.suppress_messages { NarrowHourglassSubscriptionsToLinkedTeams.new.migrate(:up) }
  end

  test 'keeps linked teams, deactivates the rest and narrows the callback token' do
    migrate!

    assert_equal [@linked.id, @legacy.id].sort, @integration.active_subscriptions.pluck(:team_id).sort
    assert_not @integration.hourglass_channel_subscriptions.find_by(team: @idle).active?
    assert_equal [@linked.id, @legacy.id].sort, @token.reload.scoped_team_ids.sort
    assert @token.team_scoped?
  end

  test 'legacy links without an integration id are not claimed when the workspace has several servers' do
    other_token = ApiToken.generate_for(@user, name: 'cb2', teams: @workspace.teams)
    other = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv_n', base_url: 'https://hg2.test', active: true, callback_api_token: other_token
    )
    other.hourglass_channel_subscriptions.create!(team: @idle, hourglass_server_id: 'srv_n', active: true)

    migrate!

    assert_equal [@linked.id], @integration.active_subscriptions.pluck(:team_id)
    assert_empty other.active_subscriptions
    assert_empty other_token.reload.scoped_team_ids
    assert other_token.team_scoped?
  end

  test 'leaves revoked callback tokens alone' do
    @token.revoke!
    before = @token.scoped_team_ids.sort

    migrate!

    assert_equal before, @token.reload.scoped_team_ids.sort
  end
end
