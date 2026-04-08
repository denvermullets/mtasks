class NotificationJob < ApplicationJob
  queue_as :default

  def perform(issue_id:, actor_id:, action:, version_id: nil)
    issue = Issue.find_by(id: issue_id)
    actor = User.find_by(id: actor_id)
    return unless issue && actor

    version = version_id ? PaperTrail::Version.find_by(id: version_id) : nil
    NotificationService.call(issue: issue, actor: actor, action: action, version: version)
  end
end
