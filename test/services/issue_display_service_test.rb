require 'test_helper'

class IssueDisplayServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'display_test@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'TST')
    @team.team_memberships.create!(user: @user)

    @backlog_lane = @team.lanes.create!(name: 'Backlog', position: 0)
    @done_lane = @team.lanes.create!(name: 'Done', position: 1)

    @open_issue = @team.issues.create!(
      title: 'Open issue', lane: @backlog_lane, creator: @user
    )
    @completed_recently = @team.issues.create!(
      title: 'Completed recently', lane: @done_lane, creator: @user,
      completed_at: 2.hours.ago
    )
    @completed_last_week = @team.issues.create!(
      title: 'Completed last week', lane: @done_lane, creator: @user,
      completed_at: 3.days.ago
    )
    @completed_last_month = @team.issues.create!(
      title: 'Completed last month', lane: @done_lane, creator: @user,
      completed_at: 2.weeks.ago
    )
  end

  test 'hides completed issues when completed_filter is nil' do
    issues = @team.issues
    service = IssueDisplayService.new(issues, { completed_filter: nil }, @team)
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_not_includes filtered, @completed_recently
    assert_not_includes filtered, @completed_last_week
    assert_not_includes filtered, @completed_last_month
  end

  test 'hides completed issues when completed_filter is empty string' do
    issues = @team.issues
    service = IssueDisplayService.new(issues, { completed_filter: '' }, @team)
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_not_includes filtered, @completed_recently
    assert_not_includes filtered, @completed_last_week
    assert_not_includes filtered, @completed_last_month
  end

  test 'past_day filter shows only issues completed within 24 hours' do
    issues = @team.issues
    service = IssueDisplayService.new(issues, { completed_filter: 'past_day' }, @team)
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_includes filtered, @completed_recently
    assert_not_includes filtered, @completed_last_week
    assert_not_includes filtered, @completed_last_month
  end

  test 'past_week filter shows issues completed within 7 days' do
    issues = @team.issues
    service = IssueDisplayService.new(issues, { completed_filter: 'past_week' }, @team)
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_includes filtered, @completed_recently
    assert_includes filtered, @completed_last_week
    assert_not_includes filtered, @completed_last_month
  end

  test 'past_month filter shows issues completed within 30 days' do
    issues = @team.issues
    service = IssueDisplayService.new(issues, { completed_filter: 'past_month' }, @team)
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_includes filtered, @completed_recently
    assert_includes filtered, @completed_last_week
    assert_includes filtered, @completed_last_month
  end

  test 'all_completed filter shows all issues including completed' do
    issues = @team.issues
    service = IssueDisplayService.new(issues, { completed_filter: 'all_completed' }, @team)
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_includes filtered, @completed_recently
    assert_includes filtered, @completed_last_week
    assert_includes filtered, @completed_last_month
  end
end
