class HourglassNotifyLinkCreatedJob < ApplicationJob
  queue_as :default

  retry_on Hourglass::ApiClient::Error, wait: :exponentially_longer, attempts: 3

  def perform(link_id)
    link = HourglassLink.find_by(id: link_id)
    return unless link&.project_channel?

    integration = link.hourglass_integration
    return unless integration&.active?

    Hourglass::WebhookDispatcher.call(
      integration: integration,
      event_type: 'link.created',
      data: {
        link_type: 'project_channel',
        hourglass_channel_id: link.hourglass_channel_id,
        mtasks_team_id: link.team_id,
        mtasks_project_id: link.mtasks_project_id,
        created_by_user_id: link.created_by_user_id
      }
    )
  rescue Hourglass::ApiClient::NotFound => e
    Rails.logger.warn("HourglassNotifyLinkCreatedJob link #{link_id}: #{e.message}; leaving active")
  rescue Hourglass::ApiClient::Unauthorized => e
    Rails.logger.warn("HourglassNotifyLinkCreatedJob marking link #{link_id} broken: #{e.message}")
    link&.update(status: 'broken')
  end
end
