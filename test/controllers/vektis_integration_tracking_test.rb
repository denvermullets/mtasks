require 'test_helper'

# The web half of VEK-585: integration setup a user performs in a page.
#
# These emit the same (feature_id, action) pairs the webhook handlers do — a channel link is a
# channel link however it was made — and `via` is the only thing that separates them. That is the
# whole reason integration features carry `via` when the rest of the server catalog does not.
class VektisIntegrationTrackingTest < ActionDispatch::IntegrationTest
  include VektisEventTestHelper

  setup do
    @user = User.create!(name: 'Web Int', email: "web_int_#{SecureRandom.hex(4)}@example.com",
                         password: 'password')
    @workspace = Workspace.create!(name: 'Web WS', owner: @user)
    @team = @workspace.teams.create!(name: 'Web Team', identifier: 'WEB')
    @team.team_memberships.create!(user: @user)
    enable_vektis!(@team)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)
    @project = @team.projects.create!(name: 'Web Project')
    @issue = @team.issues.create!(title: 'Web issue', lane: @lane, creator: @user)

    sign_in_as(@user)
    clear_enqueued_jobs
  end

  def hourglass_integration
    @workspace.hourglass_integrations.create!(
      hourglass_server_id: "srv_#{SecureRandom.hex(4)}", base_url: 'https://hg.test',
      api_token: 'tok', webhook_secret: 'wh', connected_by_user: @user
    )
  end

  def assert_web_origin(feature_id, action, provider)
    event = event_for(feature_id, action)
    assert_not_nil event, "expected #{feature_id}/#{action} in #{pairs.inspect}"
    assert_equal 'web', event['properties']['via']
    assert_equal provider, event['properties']['provider']
    assert_equal @user.id.to_s, event['user_id'], 'a web action has a user; a webhook does not'
    assert_taxonomy_conformant(event)
  end

  # --- Hourglass --------------------------------------------------------------------------------

  test 'linking a project to a channel emits hourglass-integration/link for a project' do
    hourglass_integration

    post team_project_hourglass_channel_link_path(@team, @project),
         params: { hourglass_channel_id: 'C1', hourglass_channel_name: 'launch-room' },
         headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

    assert_web_origin('hourglass-integration', 'link', 'hourglass')
    assert_equal 'project', event_for('hourglass-integration', 'link')['properties']['entity']
    assert_no_user_content 'launch-room', @project.name
  end

  test 'unlinking a channel emits hourglass-integration/unlink' do
    integration = hourglass_integration
    @team.hourglass_links.create!(link_type: 'project_channel', mtasks_project: @project,
                                  hourglass_channel_id: 'C1', hourglass_channel_name: 'general',
                                  hourglass_integration: integration, created_by_user: @user,
                                  status: 'active')

    delete team_project_hourglass_channel_link_path(@team, @project),
           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

    assert_web_origin('hourglass-integration', 'unlink', 'hourglass')
    assert_equal 'project', event_for('hourglass-integration', 'unlink')['properties']['entity']
  end

  test 'linking an issue to a thread emits hourglass-integration/link for an issue' do
    hourglass_integration

    post team_issue_hourglass_thread_link_path(@team, @issue),
         params: { hourglass_thread_id: 'T1' },
         headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

    assert_web_origin('hourglass-integration', 'link', 'hourglass')
    assert_equal 'issue', event_for('hourglass-integration', 'link')['properties']['entity']
    assert_no_user_content @issue.title
  end

  test 'a rejected thread link emits nothing' do
    hourglass_integration

    post team_issue_hourglass_thread_link_path(@team, @issue),
         params: { hourglass_thread_id: '' },
         headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

    assert_empty emitted, 'a validation failure is not integration usage'
  end

  # The Hourglass settings screen is workspace-scoped: its route carries workspace_id, so
  # current_team is only whatever the session last held, and HourglassIntegration has no team_id to
  # fall back on. A workspace owner who belongs to no team has no current_team at all. There is no
  # honest tenant to bill a connect or disconnect to, so nothing is emitted — see
  # Settings::HourglassIntegrationsController#tracked_team.
  test 'connecting or disconnecting Hourglass emits nothing, having no single team' do
    hourglass_integration

    delete workspace_settings_hourglass_integration_path(@workspace)

    assert_empty emitted
  end
end
