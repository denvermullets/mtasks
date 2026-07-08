require 'test_helper'

class IssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Test User', email: 'issues_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'TST')
    @team.team_memberships.create!(user: @user)

    @backlog_lane = @team.lanes.create!(name: 'Backlog', position: 0)
    @done_lane = @team.lanes.create!(name: 'Done', position: 1)

    @issue = @team.issues.create!(
      title: 'Test issue', lane: @backlog_lane, creator: @user
    )

    sign_in_as(@user)
  end

  test 'sets completed_at when moving issue to Done lane' do
    assert_nil @issue.completed_at

    patch team_issue_path(@team, @issue), params: { issue: { lane_id: @done_lane.id } }

    @issue.reload
    assert_not_nil @issue.completed_at
  end

  test 'clears completed_at when moving issue out of Done lane' do
    @issue.update!(lane: @done_lane, completed_at: 1.hour.ago)

    patch team_issue_path(@team, @issue), params: { issue: { lane_id: @backlog_lane.id } }

    @issue.reload
    assert_nil @issue.completed_at
  end

  test 'does not change completed_at when lane is not changing' do
    @issue.update!(lane: @done_lane, completed_at: Time.current)
    original_time = @issue.reload.completed_at

    patch team_issue_path(@team, @issue), params: { issue: { title: 'Updated title' } }

    @issue.reload
    assert_in_delta original_time, @issue.completed_at, 1.second
  end

  test 'handles case-insensitive Done lane name' do
    mixed_case_lane = @team.lanes.create!(name: 'done', position: 2)

    patch team_issue_path(@team, @issue), params: { issue: { lane_id: mixed_case_lane.id } }

    @issue.reload
    assert_not_nil @issue.completed_at
  end

  test 'card renders a hover-card fragment for the issue' do
    get card_team_issue_path(@team, @issue)
    assert_response :success
    assert_includes response.body, @issue.identifier
    assert_includes response.body, 'Test issue'
  end

  test 'card is not accessible to a user on another team' do
    other = User.create!(name: 'Outsider', email: 'outsider_card@example.com', password: 'password')
    other_workspace = Workspace.create!(name: 'Other WS', owner: other)
    other_team = other_workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
    other_team.team_memberships.create!(user: other)
    sign_in_as(other)

    get card_team_issue_path(@team, @issue)
    assert_response :redirect
    follow_redirect!
    assert_not_includes response.body, @issue.title
  end

  test 'show without a thread link offers the link affordance and keeps native comment form' do
    get team_issue_path(@team, @issue)
    assert_response :success
    assert_includes response.body, 'Link Hourglass thread'
    assert_includes response.body, 'id="comment_form"'
  end

  test 'show with a linked thread renders the Discussion section and hides the native comment form' do
    integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
      webhook_secret: 'wh', connected_by_user: @user
    )
    @team.hourglass_links.create!(
      link_type: 'issue_thread',
      mtasks_issue: @issue,
      mtasks_issue_identifier: @issue.identifier,
      hourglass_thread_id: 'T_42',
      hourglass_integration: integration,
      created_by_user: @user
    )

    get team_issue_path(@team, @issue)
    assert_response :success
    assert_includes response.body, 'linked to thread'
    assert_includes response.body, 'T_42'
    assert_includes response.body, 'discussion_composer'
    assert_not_includes response.body, 'id="comment_form"'
  end

  test 'show upserts a HourglassLinkReadState when issue has a linked thread' do
    link = @team.hourglass_links.create!(
      link_type: 'issue_thread',
      mtasks_issue: @issue,
      mtasks_issue_identifier: @issue.identifier,
      hourglass_thread_id: 'T_99',
      created_by_user: @user
    )

    assert_difference 'HourglassLinkReadState.count', 1 do
      get team_issue_path(@team, @issue)
    end
    state = HourglassLinkReadState.find_by!(user: @user, hourglass_link: link)
    original = state.last_read_at

    travel_to(2.minutes.from_now) do
      assert_no_difference 'HourglassLinkReadState.count' do
        get team_issue_path(@team, @issue)
      end
      state.reload
      assert state.last_read_at > original
    end
  end

  test 'show without a linked thread does not create a read state' do
    assert_no_difference 'HourglassLinkReadState.count' do
      get team_issue_path(@team, @issue)
    end
  end

  test 'move relocates issue to another team the user belongs to' do
    other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
    other_team.team_memberships.create!(user: @user)

    patch team_issue_move_path(@team, @issue), params: { target_team_id: other_team.id }

    @issue.reload
    assert_equal other_team, @issue.team
    assert_redirected_to team_issue_path(other_team, @issue)
  end

  test 'move rejects a team the user does not belong to' do
    foreign_team = @workspace.teams.create!(name: 'Foreign', identifier: 'FRN')

    patch team_issue_move_path(@team, @issue), params: { target_team_id: foreign_team.id }

    assert_equal @team, @issue.reload.team
    assert_redirected_to team_issue_path(@team, @issue)
  end
end
