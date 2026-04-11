class IssueAfterUpdateJob < ApplicationJob
  queue_as :default

  def perform(issue_id:, user_id:, description_changed: false)
    issue = Issue.find_by(id: issue_id)
    return unless issue

    issue.remove_blocking_dependencies!

    return unless description_changed

    user = User.find_by(id: user_id)
    return unless user

    IssueReferenceService.call(
      source_issue: issue,
      text: issue.description,
      source_type: 'description',
      user: user
    )
  end
end
