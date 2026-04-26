require 'test_helper'

# rubocop:disable Metrics/ClassLength
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

  test 'canceled issues are hidden by default' do
    canceled = @team.issues.create!(
      title: 'Canceled', lane: @backlog_lane, creator: @user, canceled_at: 1.hour.ago
    )

    service = IssueDisplayService.new(@team.issues, { completed_filter: nil }, @team)
    assert_not_includes service.filter_issues, canceled
  end

  test 'canceled issues are visible under all_completed and all_time filters' do
    canceled = @team.issues.create!(
      title: 'Canceled', lane: @backlog_lane, creator: @user, canceled_at: 1.hour.ago
    )

    %w[all_completed all_time].each do |filter|
      service = IssueDisplayService.new(@team.issues, { completed_filter: filter }, @team)
      assert_includes service.filter_issues, canceled, "expected canceled issue visible under #{filter}"
    end
  end

  test 'canceled issues respect the past_* time window the same way completed issues do' do
    cancelled_lane = @team.lanes.create!(name: 'Cancelled', position: 2)
    canceled_recently = @team.issues.create!(
      title: 'C-recent', lane: cancelled_lane, creator: @user, canceled_at: 2.hours.ago
    )
    canceled_last_week = @team.issues.create!(
      title: 'C-week', lane: cancelled_lane, creator: @user, canceled_at: 3.days.ago
    )
    canceled_last_month = @team.issues.create!(
      title: 'C-month', lane: cancelled_lane, creator: @user, canceled_at: 2.weeks.ago
    )

    past_day = IssueDisplayService.new(@team.issues, { completed_filter: 'past_day' }, @team).filter_issues
    assert_includes past_day, canceled_recently
    assert_not_includes past_day, canceled_last_week
    assert_not_includes past_day, canceled_last_month

    past_week = IssueDisplayService.new(@team.issues, { completed_filter: 'past_week' }, @team).filter_issues
    assert_includes past_week, canceled_recently
    assert_includes past_week, canceled_last_week
    assert_not_includes past_week, canceled_last_month

    past_month = IssueDisplayService.new(@team.issues, { completed_filter: 'past_month' }, @team).filter_issues
    assert_includes past_month, canceled_recently
    assert_includes past_month, canceled_last_week
    assert_includes past_month, canceled_last_month
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

  test 'label filter combined with any order_by does not raise an ambiguous-column error' do
    label = @team.labels.create!(name: 'mcp', color: '#FFFFFF')
    @open_issue.labels << label

    base_issues = @team.issues.not_archived.includes(
      :lane, :project, :labels, :assignee,
      :blocking_dependencies, :blocked_dependencies, :comments
    )

    %w[manual priority due_date created_at updated_at].each do |order_by|
      service = IssueDisplayService.new(
        base_issues,
        { completed_filter: 'all_completed', group_by: 'lane', order_by: order_by, label_ids: [label.id] },
        @team
      )
      assert_nothing_raised do
        service.grouped_issues
      rescue StandardError => e
        raise "order_by=#{order_by} raised: #{e.class}: #{e.message}"
      end
    end
  end

  test 'group_by lane returns lane-keyed buckets with correct membership' do
    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', group_by: 'lane' }, @team
    )
    grouped = service.grouped_issues

    assert_equal %w[Backlog Done], grouped.keys
    assert_includes grouped['Backlog'][:issues], @open_issue
    assert_equal 3, grouped['Done'][:issues].size
    assert_equal @backlog_lane, grouped['Backlog'][:object]
  end

  test 'group_by lane skips empty lanes when show_empty_groups is false' do
    extra = @team.lanes.create!(name: 'Empty', position: 2)

    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', group_by: 'lane' }, @team
    )
    grouped = service.grouped_issues

    assert_not_includes grouped.keys, 'Empty'
    assert_includes service.empty_groups.map { |g| g[:object] }, extra
  end

  test 'group_by priority returns priority buckets' do
    @open_issue.update!(priority: :urgent)
    @completed_recently.update!(priority: :urgent)
    @completed_last_week.update!(priority: :high)

    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', group_by: 'priority' }, @team
    )
    grouped = service.grouped_issues

    assert_equal 2, grouped['Urgent'][:issues].size
    assert_equal 1, grouped['High'][:issues].size
    assert_equal 'urgent', grouped['Urgent'][:object]
  end

  test 'group_by project includes a No Project bucket for unassigned issues' do
    project = @team.projects.create!(name: 'Alpha')
    in_project = @team.issues.create!(title: 'P1', lane: @backlog_lane, creator: @user, project: project)

    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', group_by: 'project' }, @team
    )
    grouped = service.grouped_issues

    assert_includes grouped['Alpha'][:issues], in_project
    assert_includes grouped['No Project'][:issues], @open_issue
  end

  test 'group_by label buckets issues into each of their labels' do
    bug = @team.labels.create!(name: 'bug', color: '#FF0000')
    feature = @team.labels.create!(name: 'feature', color: '#00FF00')
    @open_issue.labels << bug
    @open_issue.labels << feature
    @completed_recently.labels << feature

    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', group_by: 'label' }, @team
    )
    grouped = service.grouped_issues

    assert_includes grouped['bug'][:issues], @open_issue
    assert_includes grouped['feature'][:issues], @open_issue
    assert_includes grouped['feature'][:issues], @completed_recently
    assert_includes grouped['No Label'][:issues], @completed_last_week
  end

  test 'group_by none returns a single All Issues bucket' do
    service = IssueDisplayService.new(
      @team.issues, { completed_filter: 'all_completed', group_by: 'none' }, @team
    )
    grouped = service.grouped_issues

    assert_equal ['All Issues'], grouped.keys
    assert_equal 4, grouped['All Issues'][:issues].size
  end

  test 'sub_group_by combines primary and secondary grouping' do
    @open_issue.update!(priority: :urgent)
    @completed_recently.update!(priority: :high)

    service = IssueDisplayService.new(
      @team.issues,
      { completed_filter: 'all_completed', group_by: 'lane', sub_group_by: 'priority' },
      @team
    )
    grouped = service.grouped_issues

    assert grouped['Backlog'][:subgroups].present?
    assert_includes grouped['Backlog'][:subgroups]['Urgent'][:issues], @open_issue
    assert_includes grouped['Done'][:subgroups]['High'][:issues], @completed_recently
  end
end
# rubocop:enable Metrics/ClassLength
