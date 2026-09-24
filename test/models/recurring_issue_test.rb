require 'test_helper'

class RecurringIssueTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Ryan', email: "ri-#{SecureRandom.hex(4)}@example.com", password: 'password')
    @workspace = Workspace.create!(name: 'Acme', owner: @user)
    @team = @workspace.teams.create!(name: 'Engineering', identifier: 'RCI')
    @team.team_memberships.create!(user: @user)
  end

  def build(**attrs)
    @team.recurring_issues.new({ title: 'Deploy', creator: @user, frequency: :weekly, weekday: 5 }.merge(attrs))
  end

  # 2026-09-23 is a Wednesday.
  WEDNESDAY = Date.new(2026, 9, 23)

  test 'weekly schedule snaps to the next matching weekday' do
    record = build
    record.schedule_from(WEDNESDAY, today: WEDNESDAY)

    assert_equal Date.new(2026, 9, 25), record.next_run_on
    assert record.valid?
  end

  test 'a start date in the past is moved up to today' do
    record = build(frequency: :daily)
    record.schedule_from(WEDNESDAY - 10, today: WEDNESDAY)

    assert_equal WEDNESDAY, record.next_run_on
  end

  test 'monthly schedule clamps to the end of short months' do
    record = build(frequency: :monthly, day_of_month: 31)
    record.schedule_from(Date.new(2026, 11, 1), today: WEDNESDAY)

    assert_equal Date.new(2026, 11, 30), record.next_run_on
  end

  test 'monthly schedule rolls to next month when the day has passed' do
    record = build(frequency: :monthly, day_of_month: 5)
    record.schedule_from(WEDNESDAY, today: WEDNESDAY)

    assert_equal Date.new(2026, 10, 5), record.next_run_on
  end

  test 'spawn files an issue from the template and advances the schedule' do
    label = @team.labels.create!(name: 'ops', color: '#fff')
    record = build(description: 'Checklist', priority: :high, assignee: @user, label_ids: [label.id])
    record.schedule_from(WEDNESDAY, today: WEDNESDAY)
    record.save!

    issue = record.spawn!(today: Date.new(2026, 9, 25))

    assert_equal 'Deploy', issue.title
    assert_equal 'Checklist', issue.description
    assert issue.high?
    assert_equal @user, issue.assignee
    assert_equal @user, issue.creator
    assert_equal [label], issue.labels.to_a
    assert_equal @team.lanes.first, issue.lane
    assert_equal record, issue.recurring_issue
    assert_equal Date.new(2026, 10, 2), record.reload.next_run_on
    assert_not_nil record.last_run_at
  end

  test 'spawn skips missed occurrences instead of back-filling' do
    record = build(frequency: :daily, next_run_on: WEDNESDAY - 5)
    record.save!

    assert_difference -> { @team.issues.count }, 1 do
      record.spawn!(today: WEDNESDAY)
    end
    assert_equal WEDNESDAY + 1, record.reload.next_run_on
    assert_nil record.spawn!(today: WEDNESDAY)
  end

  test 'spawn does nothing for a paused template' do
    record = build(frequency: :daily, next_run_on: WEDNESDAY, active: false)
    record.save!

    assert_no_difference -> { @team.issues.count } do
      assert_nil record.spawn!(today: WEDNESDAY)
    end
  end

  test 'an assignee who left the team is dropped from spawned issues' do
    other = User.create!(name: 'Gone', email: "gone-#{SecureRandom.hex(4)}@example.com", password: 'password')
    record = build(frequency: :daily, next_run_on: WEDNESDAY, assignee: other)
    record.save!

    assert_nil record.spawn!(today: WEDNESDAY).assignee
  end

  test 'today is read in the template time zone' do
    travel_to Time.utc(2026, 9, 24, 3, 0) do
      assert_equal Date.new(2026, 9, 24), build(time_zone: 'UTC').local_today
      assert_equal Date.new(2026, 9, 23), build(time_zone: 'Pacific Time (US & Canada)').local_today
    end
  end

  test 'an unknown time zone is invalid' do
    record = build(time_zone: 'Mars/Olympus', next_run_on: WEDNESDAY)

    assert_not record.valid?
    assert_includes record.errors.attribute_names, :time_zone
  end

  test 'schedule summary reads naturally' do
    assert_equal 'Every week on Friday', build.schedule_summary
    assert_equal 'Every 2 months on the 15th',
                 build(frequency: :monthly, interval: 2, day_of_month: 15).schedule_summary
    assert_equal 'Every day', build(frequency: :daily).schedule_summary
  end
end
