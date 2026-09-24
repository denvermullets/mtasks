require 'test_helper'

class IssueTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'issue_model@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'IST')
    @team.team_memberships.create!(user: @user)
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @done = @team.lanes.create!(name: 'Done', position: 1)
  end

  test 'title is required' do
    issue = @team.issues.new(title: '', lane: @backlog, creator: @user)
    assert_not issue.valid?
  end

  test 'assigns team_number on create' do
    issue = @team.issues.create!(title: 'First', lane: @backlog, creator: @user)
    assert_not_nil issue.team_number
  end

  test 'identifier combines team identifier and number' do
    issue = @team.issues.create!(title: 'Test', lane: @backlog, creator: @user)
    assert_equal "IST-#{issue.team_number}", issue.identifier
  end

  # Blocking relationships
  test 'blocked_issues returns issues this one blocks' do
    issue_a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
    issue_b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
    IssueDependency.create!(blocking_issue: issue_a, blocked_issue: issue_b)

    assert_includes issue_a.blocked_issues, issue_b
  end

  test 'blocking_issues returns issues that block this one' do
    issue_a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
    issue_b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
    IssueDependency.create!(blocking_issue: issue_a, blocked_issue: issue_b)

    assert_includes issue_b.blocking_issues, issue_a
  end

  test 'remove_blocking_dependencies! removes blocking deps when completed' do
    issue_a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
    issue_b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
    IssueDependency.create!(blocking_issue: issue_a, blocked_issue: issue_b)

    issue_a.update!(completed_at: Time.current)
    issue_a.remove_blocking_dependencies!
    assert_equal 0, issue_a.reload.blocking_dependencies.count
  end

  test 'remove_blocking_dependencies! does not remove blocked_by dependencies' do
    issue_a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
    issue_b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
    IssueDependency.create!(blocking_issue: issue_b, blocked_issue: issue_a)

    issue_a.update!(completed_at: Time.current)
    issue_a.remove_blocking_dependencies!
    assert_equal 1, issue_a.reload.blocked_dependencies.count
  end

  # Project association
  test 'can belong to a project' do
    project = @team.projects.create!(name: 'My Project')
    issue = @team.issues.create!(title: 'Test', lane: @backlog, creator: @user, project: project)

    assert_equal project, issue.project
    assert_includes project.issues, issue
  end

  # Scopes
  test 'not_archived excludes archived issues' do
    issue = @team.issues.create!(title: 'Archived', lane: @backlog, creator: @user, archived_at: Time.current)
    assert_not_includes @team.issues.not_archived, issue
  end

  test 'not_completed excludes completed issues' do
    issue = @team.issues.create!(title: 'Completed', lane: @backlog, creator: @user, completed_at: Time.current)
    assert_not_includes @team.issues.not_completed, issue
  end

  test 'apply_lane_timestamps! sets canceled_at when moving to a Cancelled lane' do
    cancelled = @team.lanes.create!(name: 'Cancelled', position: 2)
    issue = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)

    issue.lane_id = cancelled.id
    issue.apply_lane_timestamps!

    assert_not_nil issue.canceled_at
    assert_nil issue.completed_at
  end

  test 'apply_lane_timestamps! also matches a Canceled (US spelling) lane' do
    canceled = @team.lanes.create!(name: 'Canceled', position: 2)
    issue = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)

    issue.lane_id = canceled.id
    issue.apply_lane_timestamps!

    assert_not_nil issue.canceled_at
  end

  test 'apply_lane_timestamps! clears canceled_at when moving away from a Cancelled lane' do
    cancelled = @team.lanes.create!(name: 'Cancelled', position: 2)
    issue = @team.issues.create!(
      title: 'A', lane: cancelled, creator: @user, canceled_at: 1.day.ago
    )

    issue.lane_id = @backlog.id
    issue.apply_lane_timestamps!

    assert_nil issue.canceled_at
  end

  test 'matching_search finds an issue by its identifier, case insensitively' do
    issue = @team.issues.create!(title: 'Searchable', lane: @backlog, creator: @user)

    assert_equal [issue], @team.issues.matching_search(issue.identifier).to_a
    assert_equal [issue], @team.issues.matching_search(issue.identifier.downcase).to_a
  end

  test 'matching_search finds an issue by a bare team number' do
    issue = @team.issues.create!(title: 'Searchable', lane: @backlog, creator: @user)

    assert_equal [issue], @team.issues.matching_search(issue.team_number.to_s).to_a
  end

  test 'matching_search ignores an identifier whose prefix belongs to another team' do
    issue = @team.issues.create!(title: 'Searchable', lane: @backlog, creator: @user)

    assert_empty @team.issues.matching_search("ZZZ-#{issue.team_number}").to_a
  end

  test 'matching_search falls back to title, and to description only when asked' do
    issue = @team.issues.create!(
      title: 'Unique Title', description: 'Unique Body', lane: @backlog, creator: @user
    )

    assert_equal [issue], @team.issues.matching_search('unique tit').to_a
    assert_empty @team.issues.matching_search('unique bod').to_a
    assert_equal [issue], @team.issues.matching_search('unique bod', include_description: true).to_a
  end

  test 'matching_search returns the full scope for a blank term' do
    @team.issues.create!(title: 'A', lane: @backlog, creator: @user)

    assert_equal @team.issues.count, @team.issues.matching_search('  ').count
  end

  # Dashboard scopes
  test 'unresolved excludes archived, completed and canceled issues' do
    open_issue = @team.issues.create!(title: 'Open', lane: @backlog, creator: @user)
    archived = @team.issues.create!(title: 'Archived', lane: @backlog, creator: @user)
    completed = @team.issues.create!(title: 'Completed', lane: @backlog, creator: @user)
    canceled = @team.issues.create!(title: 'Canceled', lane: @backlog, creator: @user)
    archived.update_columns(archived_at: Time.current)
    completed.update_columns(completed_at: Time.current)
    canceled.update_columns(canceled_at: Time.current)

    assert_equal [open_issue], @team.issues.unresolved.to_a
  end

  test 'due_on_or_before includes past and same-day dates and excludes nil and later dates' do
    today = Date.new(2026, 9, 23)
    overdue = @team.issues.create!(title: 'Overdue', lane: @backlog, creator: @user, due_date: today - 3)
    due_today = @team.issues.create!(title: 'Today', lane: @backlog, creator: @user, due_date: today)
    @team.issues.create!(title: 'Tomorrow', lane: @backlog, creator: @user, due_date: today + 1)
    @team.issues.create!(title: 'No date', lane: @backlog, creator: @user)

    assert_equal [overdue, due_today].sort_by(&:id), @team.issues.due_on_or_before(today).order(:id).to_a
  end

  test 'due_between includes both ends of the range' do
    from = Date.new(2026, 9, 23)
    to = from + 7
    first = @team.issues.create!(title: 'First', lane: @backlog, creator: @user, due_date: from)
    last = @team.issues.create!(title: 'Last', lane: @backlog, creator: @user, due_date: to)
    @team.issues.create!(title: 'Before', lane: @backlog, creator: @user, due_date: from - 1)
    @team.issues.create!(title: 'After', lane: @backlog, creator: @user, due_date: to + 1)
    @team.issues.create!(title: 'No date', lane: @backlog, creator: @user)

    assert_equal [first, last], @team.issues.due_between(from, to).order(:id).to_a
  end

  test 'hot returns only urgent and high priority issues' do
    urgent = @team.issues.create!(title: 'Urgent', lane: @backlog, creator: @user, priority: :urgent)
    high = @team.issues.create!(title: 'High', lane: @backlog, creator: @user, priority: :high)
    @team.issues.create!(title: 'Medium', lane: @backlog, creator: @user, priority: :medium)
    @team.issues.create!(title: 'Low', lane: @backlog, creator: @user, priority: :low)
    @team.issues.create!(title: 'None', lane: @backlog, creator: @user, priority: :no_priority)

    assert_equal [urgent, high], @team.issues.hot.order(:id).to_a
  end
end
