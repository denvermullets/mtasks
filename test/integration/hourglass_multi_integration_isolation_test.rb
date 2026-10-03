require 'test_helper'
require 'webmock/minitest'

# One user in four teams. Hourglass server X is connected to T1 and T2, server Y to T3, and T4 is a
# control team with no connection. Every other Hourglass test sets up a single integration, which is
# how JAIT-251..256 slipped through; these pin down that the two connections never bleed into each
# other.
class HourglassMultiIntegrationIsolationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  X_BASE = 'https://hg-x.test'.freeze
  Y_BASE = 'https://hg-y.test'.freeze
  X_SECRET = 'whsec_server_x'.freeze
  Y_SECRET = 'whsec_server_y'.freeze

  setup do
    WebMock.disable_net_connect!
    @user = User.create!(name: 'Multi', email: "multi_#{SecureRandom.hex(4)}@example.com", password: 'password')
    @workspace = Workspace.create!(name: 'Multi WS', owner: @user)
    @t1, @t2, @t3, @t4 = %w[MTA MTB MTC MTD].map do |identifier|
      @workspace.teams.create!(name: identifier, identifier: identifier).tap do |team|
        team.team_memberships.create!(user: @user)
      end
    end
    sign_in_as(@user)
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_server(base:, server_id:, integration_id:, secret:, channels:)
    stub_request(:get, "#{base}/api/v1/me")
      .to_return(json(server: { id: server_id, name: server_id.upcase },
                      integration: { id: integration_id, webhook_secret: secret }))
    stub_request(:get, "#{base}/api/v1/servers/#{server_id}/channels").to_return(json(channels: channels))
  end

  def stub_x
    stub_server(base: X_BASE, server_id: 'srv_x', integration_id: 101, secret: X_SECRET,
                channels: [{ id: 'CX1', name: 'x-general' }])
  end

  def stub_y
    stub_server(base: Y_BASE, server_id: 'srv_y', integration_id: 202, secret: Y_SECRET,
                channels: [{ id: 'CY1', name: 'y-general' }])
  end

  # Connects through the settings page, the way a person does it, and returns the integration plus
  # the raw callback token the page shows once.
  def connect(base:, api_token:, teams:)
    patch workspace_settings_hourglass_integration_path(@workspace),
          params: { base_url: base, api_token: api_token, team_ids: teams.map(&:id) }
    assert_redirected_to workspace_settings_hourglass_integration_path(@workspace)
    assert_nil flash[:alert]
    [HourglassIntegration.find(flash[:callback_token_integration_id]), flash[:callback_token]]
  end

  def connect_x
    stub_x
    @x, @x_token = connect(base: X_BASE, api_token: 'tok_x', teams: [@t1, @t2])
  end

  def connect_y
    stub_y
    @y, @y_token = connect(base: Y_BASE, api_token: 'tok_y', teams: [@t3])
  end

  def connect_both
    connect_x
    connect_y
  end

  def api_get(path, token)
    get path, headers: { 'Authorization' => "Bearer #{token}" }
  end

  def sign(body, secret)
    "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, body)}"
  end

  def post_inbound(integration, body:, secret:)
    post webhooks_hourglass_path(public_id: integration.public_id), params: body, headers: {
      'Content-Type' => 'application/json',
      'X-Hourglass-Event' => 'message.created',
      'X-Hourglass-Delivery' => "del_#{SecureRandom.hex(8)}",
      'X-Hourglass-Signature-256' => sign(body, secret)
    }
  end

  def project_in(team)
    team.projects.create!(name: "#{team.identifier} project")
  end

  def issue_in(team, project)
    lane = team.lanes.create!(name: 'Backlog', position: 0)
    team.issues.create!(title: 'Isolated', lane: lane, project: project, creator: @user)
  end

  def channels_seen_by(team)
    get channels_team_project_hourglass_channel_link_path(team, project_in(team)), as: :json
    assert_response :success
    JSON.parse(response.body)
  end

  # --- Connecting --------------------------------------------------------------------------------

  test "connecting Y leaves X's integration, secret and callback token alone" do
    connect_x
    x_before = @x.reload.attributes.slice('api_token', 'base_url', 'webhook_secret', 'callback_api_token_id',
                                          'hourglass_integration_id', 'active')
    x_scope_before = @x.callback_api_token.scoped_team_ids.sort

    connect_y

    assert_not_equal @x.id, @y.id
    assert_equal x_before, @x.reload.attributes.slice(*x_before.keys)
    assert_not @x.callback_api_token.revoked?
    assert_equal x_scope_before, @x.callback_api_token.scoped_team_ids.sort
    assert_equal [@t1.id, @t2.id].sort, @x.active_subscriptions.pluck(:team_id).sort
    assert_equal [@t3.id], @y.active_subscriptions.pluck(:team_id)
    assert_not_equal @x.callback_api_token_id, @y.callback_api_token_id
  end

  test 'connecting Y subscribes none of T1, T2 or T4' do
    connect_both

    assert_equal [@x], @t1.hourglass_integrations.to_a
    assert_equal [@x], @t2.hourglass_integrations.to_a
    assert_equal [@y], @t3.hourglass_integrations.to_a
    assert_empty @t4.hourglass_integrations
    assert_not @t4.hourglass_channel_subscriptions.exists?
  end

  # --- Callback tokens ---------------------------------------------------------------------------

  test "X's callback token sees T1 and T2 only" do
    connect_both

    api_get api_v1_teams_path, @x_token
    assert_response :success
    assert_equal [@t1.id, @t2.id].sort, JSON.parse(response.body).map { |t| t['id'] }.sort

    [@t3, @t4].each do |team|
      api_get api_v1_team_issues_path(team), @x_token
      assert_response :not_found, "X's token reached #{team.identifier}"
    end
  end

  test "Y's callback token sees T3 only" do
    connect_both

    api_get api_v1_teams_path, @y_token
    assert_response :success
    assert_equal([@t3.id], JSON.parse(response.body).map { |t| t['id'] })

    [@t1, @t2, @t4].each do |team|
      api_get api_v1_team_issues_path(team), @y_token
      assert_response :not_found, "Y's token reached #{team.identifier}"
    end
  end

  # --- Channel picker ----------------------------------------------------------------------------

  test "the channel picker for T1 lists only X's channels" do
    connect_both
    WebMock.reset!
    x_channels = stub_x
    y_channels = stub_y

    assert_equal(['x-general'], channels_seen_by(@t1).map { |c| c['name'] })
    assert_requested x_channels
    assert_not_requested y_channels
  end

  test "the channel picker for T3 lists only Y's channels" do
    connect_both
    WebMock.reset!
    x_channels = stub_x
    y_channels = stub_y

    assert_equal(['y-general'], channels_seen_by(@t3).map { |c| c['name'] })
    assert_requested y_channels
    assert_not_requested x_channels
  end

  test 'the channel picker for T4 lists nothing and calls neither server' do
    connect_both
    WebMock.reset!

    assert_empty channels_seen_by(@t4)
    assert_not_requested :any, /hg-[xy]\.test/
  end

  # --- Link creation -----------------------------------------------------------------------------

  test "a T1 link naming Y's integration is rejected" do
    connect_both
    project = project_in(@t1)
    stub_request(:get, "#{Y_BASE}/api/v1/channels/CY1").to_return(json(id: 'CY1', server_id: 'srv_y'))

    assert_no_difference 'HourglassLink.count' do
      post team_project_hourglass_channel_link_path(@t1, project),
           params: { hourglass_channel_id: 'CY1', hourglass_channel_name: 'y-general',
                     hourglass_integration_id: @y.id },
           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    end
    assert_includes response.body, 'subscribed to'
  end

  test "a T1 link pairing X's integration with Y's channel is rejected" do
    connect_both
    project = project_in(@t1)
    # X's token can't see a channel on Y, so X answers 404.
    stub_request(:get, "#{X_BASE}/api/v1/channels/CY1").to_return(status: 404, body: '{}')

    assert_no_difference 'HourglassLink.count' do
      post team_project_hourglass_channel_link_path(@t1, project),
           params: { hourglass_channel_id: 'CY1', hourglass_channel_name: 'y-general',
                     hourglass_integration_id: @x.id },
           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    end
    assert_includes response.body, 'isn&#39;t on the selected Hourglass server'
  end

  test "link services refuse to pair a T1 project or issue with Y's integration" do
    connect_both
    project = project_in(@t1)
    issue = issue_in(@t1, project)

    channel = HourglassLinks::CreateService.call(project: project, channel_id: 'CY1', channel_name: 'y',
                                                 integration: @y, current_user: @user, notify_outbound: false)
    thread = HourglassLinks::CreateThreadService.call(issue: issue, hourglass_thread_id: 'TY1',
                                                      integration: @y, current_user: @user, notify_outbound: false)

    assert_equal HourglassLinks::CreateService::NOT_SUBSCRIBED_ERROR, channel.error
    assert_equal HourglassLinks::CreateThreadService::NOT_SUBSCRIBED_ERROR, thread.error
    assert_not HourglassLink.exists?(team: @t1)
  end

  # --- Inbound webhooks --------------------------------------------------------------------------

  test 'inbound webhooks for X and Y each verify with their own secret' do
    connect_both
    body = { version: 1, message_id: 'm1', body: 'hi' }.to_json

    assert_enqueued_with(job: HourglassWebhookProcessorJob, args: ->(args) { args.first == @x.id }) do
      post_inbound(@x, body: body, secret: X_SECRET)
    end
    assert_response :ok

    assert_enqueued_with(job: HourglassWebhookProcessorJob, args: ->(args) { args.first == @y.id }) do
      post_inbound(@y, body: body, secret: Y_SECRET)
    end
    assert_response :ok
  end

  test "an inbound webhook signed with the other server's secret is rejected" do
    connect_both
    body = { version: 1, message_id: 'm2', body: 'hi' }.to_json

    assert_no_enqueued_jobs(only: HourglassWebhookProcessorJob) do
      post_inbound(@x, body: body, secret: Y_SECRET)
      assert_response :unauthorized
      post_inbound(@y, body: body, secret: X_SECRET)
      assert_response :unauthorized
    end
  end

  # --- Outbound ----------------------------------------------------------------------------------

  def link_t3_to_y
    project = project_in(@t3)
    issue = issue_in(@t3, project)
    channel = @t3.hourglass_links.create!(link_type: 'project_channel', mtasks_project: project,
                                          hourglass_channel_id: 'CY1', hourglass_channel_name: 'y-general',
                                          hourglass_integration: @y, created_by_user: @user)
    thread = @t3.hourglass_links.create!(link_type: 'issue_thread', mtasks_issue: issue,
                                         mtasks_issue_identifier: issue.identifier,
                                         hourglass_thread_id: 'TY1', hourglass_integration: @y,
                                         created_by_user: @user)
    [issue, channel, thread]
  end

  test "the outbound emitter for a T3 issue only calls Y with Y's token" do
    connect_both
    issue, = link_t3_to_y
    WebMock.reset!
    to_channel = stub_request(:post, "#{Y_BASE}/api/v1/channels/CY1/messages")
                 .with(headers: { 'Authorization' => 'Bearer tok_y' })
                 .to_return(json(id: 'MY1', channel_id: 'CY1'))
    to_thread = stub_request(:post, "#{Y_BASE}/api/v1/messages/TY1/replies")
                .with(headers: { 'Authorization' => 'Bearer tok_y' })
                .to_return(json(id: 'MY2', channel_id: 'CY1'))

    HourglassOutboundEmitterJob.perform_now(event_type: 'issue.created', issue_id: issue.id, actor_id: @user.id)
    HourglassOutboundEmitterJob.perform_now(event_type: 'issue.priority_changed', issue_id: issue.id,
                                            actor_id: @user.id)

    assert_requested to_channel, times: 1
    assert_requested to_thread, times: 1
    assert_not_requested :any, /hg-x\.test/
  end

  test "link-created notifications for T3 go only to Y, signed with Y's secret" do
    connect_both
    _issue, channel, thread = link_t3_to_y
    WebMock.reset!
    to_y = stub_request(:post, "#{Y_BASE}/webhooks/mtasks/202")
           .with { |req| req.headers['X-Mtasks-Signature-256'] == sign(req.body, Y_SECRET) }
           .to_return(status: 200, body: '{}')

    HourglassNotifyLinkCreatedJob.perform_now(channel.id)
    HourglassNotifyThreadLinkCreatedJob.perform_now(thread.id)

    assert_requested to_y, times: 2
    assert_not_requested :any, /hg-x\.test/
  end
end
