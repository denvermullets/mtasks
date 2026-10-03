require 'test_helper'

class HourglassThreadLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'TL', email: 'tl_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'TLC')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'L', position: 0)
    @issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
      webhook_secret: 'wh', connected_by_user: @user
    )
    HourglassIntegrations::SubscribeTeamsService.call(integration: @integration, teams: [@team])

    sign_in_as(@user)
  end

  test 'new renders the manual-paste modal' do
    get new_team_issue_hourglass_thread_link_path(@team, @issue)

    assert_response :success
    assert_includes response.body, 'Link a Hourglass thread'
    assert_includes response.body, 'Thread ID'
  end

  def post_thread(params)
    post team_issue_hourglass_thread_link_path(@team, @issue),
         params: params, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
  end

  test 'create persists an issue_thread link' do
    assert_difference 'HourglassLink.count', 1 do
      post team_issue_hourglass_thread_link_path(@team, @issue),
           params: { hourglass_thread_id: 'T_42', hourglass_integration_id: @integration.id },
           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    end

    assert_response :success
    link = HourglassLink.for_issue(@issue).first
    assert_equal 'T_42', link.hourglass_thread_id
    assert link.active?
  end

  test 'create with blank thread id renders the error frame' do
    assert_no_difference 'HourglassLink.count' do
      post team_issue_hourglass_thread_link_path(@team, @issue),
           params: { hourglass_thread_id: '', hourglass_integration_id: @integration.id },
           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    end

    assert_response :success
    assert_includes response.body, 'Could not link thread'
  end

  test 'destroy removes the link' do
    @team.hourglass_links.create!(
      link_type: 'issue_thread',
      mtasks_issue: @issue,
      mtasks_issue_identifier: @issue.identifier,
      hourglass_thread_id: 'T_old',
      hourglass_integration: @integration,
      created_by_user: @user
    )

    assert_difference 'HourglassLink.count', -1 do
      delete team_issue_hourglass_thread_link_path(@team, @issue),
             headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    end

    assert_response :success
    assert_nil HourglassLink.for_issue(@issue).first
  end

  test 'new offers a server choice when the project is not channel-linked' do
    get new_team_issue_hourglass_thread_link_path(@team, @issue)

    assert_includes response.body, 'name="hourglass_integration_id"'
  end

  test "create uses the project's channel-link integration without a choice" do
    project = @team.projects.create!(name: 'Linked')
    @issue.update!(project: project)
    @team.hourglass_links.create!(
      link_type: 'project_channel', mtasks_project: project, hourglass_channel_id: 'C1',
      hourglass_channel_name: 'general', hourglass_integration: @integration, created_by_user: @user
    )

    assert_difference 'HourglassLink.issue_thread.count', 1 do
      post_thread(hourglass_thread_id: 'T_P')
    end

    assert_equal @integration, HourglassLink.for_issue(@issue).first.hourglass_integration
  end

  test 'create requires an explicit server choice when the project is not linked' do
    assert_no_difference 'HourglassLink.count' do
      post_thread(hourglass_thread_id: 'T_1')
    end

    assert_includes response.body, 'Choose which Hourglass server'
  end

  test 'create rejects an integration the team is not subscribed to' do
    other_team = @workspace.teams.create!(name: 'Other', identifier: 'OTL')
    other = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv_y', base_url: 'https://hg-y.test', api_token: 'tok_y',
      webhook_secret: 'wh_y', connected_by_user: @user
    )
    HourglassIntegrations::SubscribeTeamsService.call(integration: other, teams: [other_team])

    assert_no_difference 'HourglassLink.count' do
      post_thread(hourglass_thread_id: 'T_1', hourglass_integration_id: other.id)
    end

    assert_includes response.body, 'Choose which Hourglass server'
  end

  test 'create is rejected with no fallback when the team has no subscriptions' do
    @team.hourglass_channel_subscriptions.update_all(active: false)

    assert_no_difference 'HourglassLink.count' do
      post_thread(hourglass_thread_id: 'T_1', hourglass_integration_id: @integration.id)
    end

    assert_includes response.body, 'not subscribed to a Hourglass server'
  end
end
