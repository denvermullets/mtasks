# Hourly sweep (config/recurring.yml) that files an issue for every recurring template that is due.
# One failing template is logged and skipped so it can't hold up the rest of the team's schedule.
class RecurringIssuesJob < ApplicationJob
  queue_as :default

  def perform
    RecurringIssue.due_soon.includes(:team, :creator).find_each do |recurring_issue|
      issue = recurring_issue.spawn!
      HourglassOutboundEmitterJob.dispatch_create(issue, issue.creator) if issue&.creator
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("RecurringIssuesJob skipped recurring_issue=#{recurring_issue.id}: #{e.message}")
    end
  end
end
