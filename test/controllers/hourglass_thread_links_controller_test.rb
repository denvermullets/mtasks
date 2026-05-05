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

    sign_in_as(@user)
  end

  test 'new renders the manual-paste modal' do
    get new_team_issue_hourglass_thread_link_path(@team, @issue)

    assert_response :success
    assert_includes response.body, 'Link a Hourglass thread'
    assert_includes response.body, 'Thread ID'
  end

  test 'create persists an issue_thread link' do
    assert_difference 'HourglassLink.count', 1 do
      post team_issue_hourglass_thread_link_path(@team, @issue),
           params: { hourglass_thread_id: 'T_42' },
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
           params: { hourglass_thread_id: '' },
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
end
