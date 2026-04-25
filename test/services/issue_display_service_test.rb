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

  test 'project_ids filter scopes issues to selected projects' do
    project_a = @team.projects.create!(name: 'Project A')
    project_b = @team.projects.create!(name: 'Project B')
    project_c = @team.projects.create!(name: 'Project C')

    in_a = @team.issues.create!(title: 'A1', lane: @backlog_lane, creator: @user, project: project_a)
    in_b = @team.issues.create!(title: 'B1', lane: @backlog_lane, creator: @user, project: project_b)
    in_c = @team.issues.create!(title: 'C1', lane: @backlog_lane, creator: @user, project: project_c)

    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', project_ids: [project_a.id, project_b.id] }, @team
    )
    filtered = service.filter_issues

    assert_includes filtered, in_a
    assert_includes filtered, in_b
    assert_not_includes filtered, in_c
    assert_not_includes filtered, @open_issue
  end

  test 'project_ids filter is skipped when blank' do
    project = @team.projects.create!(name: 'Solo')
    in_project = @team.issues.create!(title: 'P', lane: @backlog_lane, creator: @user, project: project)

    service = IssueDisplayService.new(@team.issues, { completed_filter: 'all_completed', project_ids: nil }, @team)
    filtered = service.filter_issues

    assert_includes filtered, in_project
    assert_includes filtered, @open_issue
  end

  test 'lane_ids filter scopes issues to selected lanes' do
    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', lane_ids: [@backlog_lane.id] }, @team
    )
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_not_includes filtered, @completed_recently
  end

  test 'assignee_ids filter scopes issues to selected assignees' do
    other = User.create!(name: 'Other', email: 'other_assignee@example.com', password: 'password')
    @team.team_memberships.create!(user: other)
    @open_issue.update!(assignee: other)

    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', assignee_ids: [other.id] }, @team
    )
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_not_includes filtered, @completed_recently
  end

  test 'priority filter scopes issues to selected priorities' do
    @open_issue.update!(priority: :urgent)
    @completed_recently.update!(priority: :low)

    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', priority: %w[urgent] }, @team
    )
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_not_includes filtered, @completed_recently
  end

  test 'label_ids filter scopes issues that have any of the labels' do
    label_a = @team.labels.create!(name: 'bug', color: '#FF0000')
    label_b = @team.labels.create!(name: 'feature', color: '#00FF00')
    @open_issue.labels << label_a
    @completed_recently.labels << label_b

    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', label_ids: [label_a.id] }, @team
    )
    filtered = service.filter_issues

    assert_includes filtered, @open_issue
    assert_not_includes filtered, @completed_recently
  end
end
