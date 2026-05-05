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

  test 'create persists link and responds with turbo_stream' do
    @integration.update!(hourglass_integration_id: 7)
    stub_request(:post, "#{BASE}/webhooks/mtasks/7").to_return(status: 200, body: '{}')

    perform_enqueued_jobs do
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

    perform_enqueued_jobs do
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
end
