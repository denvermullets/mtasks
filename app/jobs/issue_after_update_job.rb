class IssueAfterUpdateJob < ApplicationJob
  queue_as :default

  def perform(issue_id:, user_id:, description_changed: false, version_id: nil)
    issue = Issue.find_by(id: issue_id)
    return unless issue

    issue.remove_blocking_dependencies!

    user = User.find_by(id: user_id)
    enqueue_outbound_emitter(issue, user, version_id) if user && version_id

    return unless description_changed && user

    IssueReferenceService.call(
      source_issue: issue,
      text: issue.description,
      source_type: 'description',
      user: user
    )
  end

  private

  def enqueue_outbound_emitter(issue, user, version_id)
    version = PaperTrail::Version.find_by(id: version_id)
    return unless version&.event == 'update'

    event_type = outbound_event_type(version)
    return unless event_type

    HourglassOutboundEmitterJob.perform_later(
      event_type: event_type, issue_id: issue.id, actor_id: user.id, version_id: version.id
    )
  end

  def outbound_event_type(version)
    case NotificationService.action_for_version(version)
    when 'changed_status'   then 'issue.status_changed'
    when 'changed_assignee' then 'issue.assigned'
    when 'changed_priority' then 'issue.priority_changed'
    else
      changes = version.object_changes || {}
      'issue.updated' if changes.key?('title') || changes.key?('description')
    end
  end
end
