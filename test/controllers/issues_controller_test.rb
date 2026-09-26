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

  test 'back link does not loop between two issues visited in turn' do
    other = @team.issues.create!(title: 'Other issue', lane: @backlog_lane, creator: @user)
    list = team_issues_path(@team, lane_ids: @backlog_lane.id)

    get team_issue_path(@team, @issue), headers: { 'Referer' => "http://www.example.com#{list}" }
    get team_issue_path(@team, other), headers: { 'Referer' => "http://www.example.com#{team_issue_path(@team, @issue)}" }
    assert_select 'a[href=?]', team_issue_path(@team, @issue)

    get team_issue_path(@team, @issue), headers: { 'Referer' => "http://www.example.com#{team_issue_path(@team, other)}" }
    assert_select 'a[href=?]', list
    assert_select 'a[href=?]', team_issue_path(@team, other), count: 0
  end

  test 'new captures the originating project and create returns there' do
    project = @team.projects.create!(name: 'Proj', status: 'backlog')
    project_path = team_project_path(@team, project)

    get new_team_issue_path(@team, project_id: project.id), headers: { 'Referer' => "http://www.example.com#{project_path}" }
    assert_select 'input[type=hidden][name=return_to][value=?]', project_path

    post team_issues_path(@team), params: { return_to: project_path,
                                            issue: { title: 'From project', lane_id: @backlog_lane.id } }
    assert_redirected_to project_path
  end

  test 'create falls back to the trail and keeps index filters' do
    list = team_issues_path(@team, lane_ids: @backlog_lane.id)
    get new_team_issue_path(@team), headers: { 'Referer' => "http://www.example.com#{list}" }

    post team_issues_path(@team), params: { issue: { title: 'Filtered', lane_id: @backlog_lane.id } }
    assert_redirected_to list
  end

  test 'create with create_more carries return_to to the next form' do
    list = team_issues_path(@team, lane_ids: @backlog_lane.id)

    post team_issues_path(@team), params: { return_to: list, create_more: '1',
                                            issue: { title: 'Again', lane_id: @backlog_lane.id } }
    assert_redirected_to new_team_issue_path(@team, return_to: list)
  end

  test 'create ignores a return_to outside the current team' do
    other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')

    post team_issues_path(@team), params: { return_to: team_issues_path(other_team),
                                            issue: { title: 'Nope', lane_id: @backlog_lane.id } }
    assert_redirected_to team_issues_path(@team)

    post team_issues_path(@team), params: { return_to: 'https://evil.example/teams/1/issues',
                                            issue: { title: 'Nope', lane_id: @backlog_lane.id } }
    assert_redirected_to team_issues_path(@team)
  end

  test 'destroy returns to the page before the deleted issue' do
    project = @team.projects.create!(name: 'Proj', status: 'backlog')
    project_path = team_project_path(@team, project)

    get team_issue_path(@team, @issue), headers: { 'Referer' => "http://www.example.com#{project_path}" }
    delete team_issue_path(@team, @issue), headers: { 'Referer' => "http://www.example.com#{team_issue_path(@team, @issue)}" }

    assert_redirected_to project_path
  end

  test 'update without new files keeps existing attachments' do
    @issue.files.attach(io: StringIO.new('one'), filename: 'one.txt', content_type: 'text/plain')

    patch team_issue_path(@team, @issue), params: { issue: { title: 'Renamed', files: [''] } }

    assert_equal(['one.txt'], @issue.reload.files.map { |f| f.filename.to_s })
  end

  test 'update with new files appends to existing attachments' do
    @issue.files.attach(io: StringIO.new('one'), filename: 'one.txt', content_type: 'text/plain')
    upload = Rack::Test::UploadedFile.new(StringIO.new('two'), 'text/plain', original_filename: 'two.txt')

    patch team_issue_path(@team, @issue), params: { issue: { files: ['', upload] } }

    assert_equal %w[one.txt two.txt], @issue.reload.files.map { |f| f.filename.to_s }.sort
  end

  test 'board dependency overlay edges include visible pairs and drop filtered-out ends' do
    todo_lane = @team.lanes.create!(name: 'Todo', position: 2)
    blocked = @team.issues.create!(title: 'Blocked', lane: @backlog_lane, creator: @user)
    hidden = @team.issues.create!(title: 'Filtered out', lane: todo_lane, creator: @user)
    IssueDependency.create!(blocking_issue: @issue, blocked_issue: blocked)
    IssueDependency.create!(blocking_issue: @issue, blocked_issue: hidden, kind: 'relates')

    get team_issues_path(@team, view_mode: 'board', show_dependencies: 'true', lane_ids: @backlog_lane.id)

    assert_response :success
    edges = nil
    assert_select '[data-controller="dependency-overlay"]', 1 do |elements|
      edges = JSON.parse(elements.first['data-dependency-overlay-edges-value'])
    end
    assert_equal [{ 'from_id' => @issue.id, 'to_id' => blocked.id, 'kind' => 'blocks' }], edges
  end

  test 'board has no dependency overlay or legend outside Deps mode' do
    get team_issues_path(@team, view_mode: 'board', show_dependencies: 'false')

    assert_response :success
    assert_select '[data-controller="dependency-overlay"]', count: 0
    assert_select '#dependency_legend.hidden', 1
    assert_select '[data-display-options-mode-value="board"]', 1
  end

  test 'Deps view mode shows the legend bar and marks the Deps segment active' do
    get team_issues_path(@team, view_mode: 'board', show_dependencies: 'true')

    assert_response :success
    assert_select '#dependency_legend:not(.hidden)', 1
    assert_select '[data-display-options-mode-value="dependencies"]', 1
    assert_select 'button[data-view-mode="dependencies"].bg-foreground', 1
  end

  test 'list view ignores show_dependencies' do
    get team_issues_path(@team, view_mode: 'list', show_dependencies: 'true')

    assert_response :success
    assert_select '#dependency_legend.hidden', 1
    assert_select '[data-display-options-mode-value="list"]', 1
  end
end
