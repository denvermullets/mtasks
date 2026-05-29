class HourglassNotifyThreadLinkCreatedJob < ApplicationJob
  queue_as :default

  retry_on Hourglass::ApiClient::Error, wait: :exponentially_longer, attempts: 3

  def perform(link_id)
    link = HourglassLink.find_by(id: link_id)
    return unless link&.issue_thread?

    integration = link.hourglass_integration
    return unless integration&.active?

    Hourglass::WebhookDispatcher.call(integration: integration, event_type: 'link.created', data: data_for(link))
  rescue Hourglass::ApiClient::NotFound => e
    Rails.logger.warn("HourglassNotifyThreadLinkCreatedJob link #{link_id}: #{e.message}; leaving active")
  rescue Hourglass::ApiClient::Unauthorized => e
    Rails.logger.warn("HourglassNotifyThreadLinkCreatedJob marking link #{link_id} broken: #{e.message}")
    link&.update(status: 'broken')
  end

  private

  def data_for(link)
    {
      link_type: 'issue_thread',
      mtasks_team_id: link.team_id,
      mtasks_issue_id: link.mtasks_issue_id,
      mtasks_issue_identifier: link.mtasks_issue_identifier,
      hourglass_thread_id: link.hourglass_thread_id,
      created_by_user_id: link.created_by_user_id
    }
  end
end
