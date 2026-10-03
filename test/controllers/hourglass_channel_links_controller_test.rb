require 'test_helper'
require 'webmock/minitest'

class HourglassChannelLinksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  BASE = 'https://hg.test'.freeze

  setup do
    WebMock.disable_net_connect!
    @user = User.create!(name: 'CL', email: 'cl_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'CLC')
    @team.team_memberships.create!(user: @user)
    @project = @team.projects.create!(name: 'Proj')
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv', base_url: BASE, api_token: 'tok',
      webhook_secret: 'wh', connected_by_user: @user
    )
    HourglassIntegrations::SubscribeTeamsService.call(integration: @integration, teams: [@team])

    sign_in_as(@user)
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
  end

  def stub_channels(channels = [{ 'id' => 'C1', 'name' => 'general' }])
    stub_request(:get, "#{BASE}/api/v1/servers/srv/channels")
      .to_return(status: 200, body: { channels: channels }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  test 'new renders the picker modal frame with channel options' do
    stub_channels([{ 'id' => 'C1', 'name' => 'general' }, { 'id' => 'C2', 'name' => 'random' }])

    get new_team_project_hourglass_channel_link_path(@team, @project)

    assert_response :success
    assert_includes response.body, 'Link a Hourglass channel'
    assert_includes response.body, 'general'
    assert_includes response.body, 'random'
  end

  def stub_channel(id, server_id:, base: BASE)
    stub_request(:get, "#{base}/api/v1/channels/#{id}")
      .to_return(status: 200, body: { id: id, server_id: server_id }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  # A second server, connected in the same workspace but subscribed only by another team.
  def other_team_integration
    other_team = @workspace.teams.create!(name: 'Other', identifier: 'OTH')
    integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv_y', base_url: 'https://hg-y.test', api_token: 'tok_y',
      webhook_secret: 'wh_y', connected_by_user: @user
    )
    HourglassIntegrations::SubscribeTeamsService.call(integration: integration, teams: [other_team])
    integration
  end

  def post_link(params)
    post team_project_hourglass_channel_link_path(@team, @project),
         params: params, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
  end

  test 'create persists link and responds with turbo_stream' do
    @integration.update!(hourglass_integration_id: 7)
    stub_channel('C1', server_id: 'srv')
    stub_request(:post, "#{BASE}/webhooks/mtasks/7").to_return(status: 200, body: '{}')

    # Scoped to the outbound notify job on purpose: Vektis::DeliveryJob also lands in the queue here
    # (VEK-585), and running it would make a live analytics request from a controller test.
    perform_enqueued_jobs(only: HourglassNotifyLinkCreatedJob) do
      assert_difference 'HourglassLink.count', 1 do
        post team_project_hourglass_channel_link_path(@team, @project),
             params: { hourglass_channel_id: 'C1', hourglass_channel_name: 'general' },
             headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end
    end

    assert_response :success
    assert_match(/turbo-stream/, @response.content_type)
    link = @project.reload.hourglass_channel_link
    assert_equal 'C1', link.hourglass_channel_id
    assert_equal 'general', link.hourglass_channel_name
  end

  test 'destroy removes link and responds with turbo_stream' do
    @integration.update!(hourglass_integration_id: 7)
    @team.hourglass_links.create!(
      link_type: 'project_channel',
      mtasks_project: @project,
      hourglass_channel_id: 'CX',
      hourglass_channel_name: 'gone',
      hourglass_integration: @integration,
      created_by_user: @user
    )
    stub_request(:post, "#{BASE}/webhooks/mtasks/7").to_return(status: 200, body: '{}')

    perform_enqueued_jobs(only: HourglassNotifyLinkDestroyedJob) do
      assert_difference 'HourglassLink.count', -1 do
        delete team_project_hourglass_channel_link_path(@team, @project),
               headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end
    end

    assert_response :success
    assert_match(/turbo-stream/, @response.content_type)
    assert_nil @project.reload.hourglass_channel_link
  end

  test 'channels endpoint returns JSON list' do
    stub_channels

    get channels_team_project_hourglass_channel_link_path(@team, @project), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.size
    assert_equal 'general', body.first['name']
  end

  test 'picker lists only channels from servers the team is subscribed to' do
    other_team_integration
    stub_channels([{ 'id' => 'C1', 'name' => 'general' }])
    other = stub_request(:get, 'https://hg-y.test/api/v1/servers/srv_y/channels')
            .to_return(status: 200, body: { channels: [{ id: 'CY', name: 'secret' }] }.to_json)

    get channels_team_project_hourglass_channel_link_path(@team, @project), as: :json

    assert_response :success
    assert_equal(['general'], JSON.parse(response.body).map { |c| c['name'] })
    assert_not_requested other
  end

  test 'create rejects an integration the team is not subscribed to' do
    other = other_team_integration
    stub_channel('CY', server_id: 'srv_y', base: 'https://hg-y.test')

    assert_no_difference 'HourglassLink.count' do
      post_link(hourglass_channel_id: 'CY', hourglass_channel_name: 'secret', hourglass_integration_id: other.id)
    end

    assert_includes response.body, 'subscribed to'
  end

  test "create rejects a channel id from another integration's server" do
    stub_channel('CY', server_id: 'srv_y')

    assert_no_difference 'HourglassLink.count' do
      post_link(hourglass_channel_id: 'CY', hourglass_channel_name: 'secret', hourglass_integration_id: @integration.id)
    end

    assert_includes response.body, 'isn&#39;t on the selected Hourglass server'
  end

  test 'create rejects a channel Hourglass does not return for this token' do
    stub_request(:get, "#{BASE}/api/v1/channels/C404").to_return(status: 404, body: '{}')

    assert_no_difference 'HourglassLink.count' do
      post_link(hourglass_channel_id: 'C404', hourglass_channel_name: 'x', hourglass_integration_id: @integration.id)
    end
  end

  test 'create requires an integration id when the team is subscribed to several servers' do
    second = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv_2', base_url: BASE, api_token: 'tok2',
      webhook_secret: 'wh2', connected_by_user: @user
    )
    HourglassIntegrations::SubscribeTeamsService.call(integration: second, teams: [@team])

    assert_no_difference 'HourglassLink.count' do
      post_link(hourglass_channel_id: 'C1', hourglass_channel_name: 'general')
    end

    assert_includes response.body, 'Select a channel'
  end

  test 'create is rejected with no fallback when the team has no subscriptions' do
    @team.hourglass_channel_subscriptions.update_all(active: false)

    assert_no_difference 'HourglassLink.count' do
      post_link(hourglass_channel_id: 'C1', hourglass_channel_name: 'general',
                hourglass_integration_id: @integration.id)
    end

    assert_includes response.body, 'not subscribed to a Hourglass server'
  end
end
