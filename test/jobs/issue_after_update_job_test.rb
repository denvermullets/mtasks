require 'test_helper'

class IssueAfterUpdateJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(name: 'Ryan', email: 'ryan_iauj@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'IAU')
    @team.team_memberships.create!(user: @user)
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @in_progress = @team.lanes.create!(name: 'In Progress', position: 1)
    @issue = @team.issues.create!(title: 'Ship', lane: @backlog, creator: @user)
  end

  def build_version(changes)
    PaperTrail::Version.create!(
      item_type: 'Issue', item_id: @issue.id, event: 'update', object_changes: changes,
      created_at: Time.current
    )
  end

  test 'no version_id leaves prior behavior unchanged (no emitter enqueued)' do
    assert_no_enqueued_jobs(only: HourglassOutboundEmitterJob) do
      IssueAfterUpdateJob.perform_now(issue_id: @issue.id, user_id: @user.id)
    end
  end

  def captured_event_type(version)
    assert_enqueued_jobs 1, only: HourglassOutboundEmitterJob do
      IssueAfterUpdateJob.perform_now(issue_id: @issue.id, user_id: @user.id, version_id: version.id)
    end
    enqueued_jobs.last[:args].first[:event_type] || enqueued_jobs.last[:args].first['event_type']
  end

  test 'lane_id change enqueues issue.status_changed' do
    assert_equal 'issue.status_changed',
                 captured_event_type(build_version('lane_id' => [@backlog.id, @in_progress.id]))
  end

  test 'assignee_id change enqueues issue.assigned' do
    assert_equal 'issue.assigned', captured_event_type(build_version('assignee_id' => [nil, @user.id]))
  end

  test 'priority change enqueues issue.priority_changed' do
    assert_equal 'issue.priority_changed',
                 captured_event_type(build_version('priority' => [Issue.priorities['low'], Issue.priorities['urgent']]))
  end

  test 'title-only change enqueues issue.updated' do
    assert_equal 'issue.updated', captured_event_type(build_version('title' => %w[Ship Sail]))
  end

  test 'no recognized changes does not enqueue an emitter' do
    version = build_version('estimate' => [nil, 3])

    assert_no_enqueued_jobs(only: HourglassOutboundEmitterJob) do
      IssueAfterUpdateJob.perform_now(issue_id: @issue.id, user_id: @user.id, version_id: version.id)
    end
  end
end
