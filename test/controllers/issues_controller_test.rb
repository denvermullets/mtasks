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
    original_time = 2.days.ago
    @issue.update!(lane: @done_lane, completed_at: original_time)

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
end
