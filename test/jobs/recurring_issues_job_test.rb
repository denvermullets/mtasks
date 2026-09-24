require 'test_helper'

class RecurringIssuesJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: 'Ryan', email: "rij-#{SecureRandom.hex(4)}@example.com", password: 'password')
    @workspace = Workspace.create!(name: 'Acme', owner: @user)
    @team = @workspace.teams.create!(name: 'Engineering', identifier: 'RIJ')
    @team.team_memberships.create!(user: @user)
  end

  def recurring(**attrs)
    @team.recurring_issues.create!({ title: 'Deploy', creator: @user, frequency: :daily }.merge(attrs))
  end

  test 'files issues only for due, active templates' do
    due = recurring(next_run_on: Date.current)
    recurring(title: 'Later', next_run_on: Date.current + 1)
    recurring(title: 'Paused', next_run_on: Date.current, active: false)

    assert_difference -> { @team.issues.count }, 1 do
      RecurringIssuesJob.perform_now
    end
    assert_equal due, @team.issues.last.recurring_issue
    assert_enqueued_jobs 1, only: HourglassOutboundEmitterJob
  end

  test 'running twice in a day files one issue' do
    recurring(next_run_on: Date.current)

    assert_difference -> { @team.issues.count }, 1 do
      2.times { RecurringIssuesJob.perform_now }
    end
  end

  # 20:00 UTC on the 23rd is already 05:00 on the 24th in Tokyo, but still the 23rd in UTC and Los Angeles.
  test 'a template is due once its own zone reaches the date' do
    travel_to Time.utc(2026, 9, 23, 20, 0) do
      utc = recurring(title: 'UTC', next_run_on: Date.new(2026, 9, 24))
      pacific = recurring(title: 'Pacific', time_zone: 'Pacific Time (US & Canada)', next_run_on: Date.new(2026, 9, 24))
      tokyo = recurring(title: 'Tokyo', time_zone: 'Tokyo', next_run_on: Date.new(2026, 9, 24))

      RecurringIssuesJob.perform_now

      assert_empty utc.issues
      assert_empty pacific.issues
      assert_equal 1, tokyo.issues.count
      assert_equal Date.new(2026, 9, 25), tokyo.reload.next_run_on
    end
  end
end
