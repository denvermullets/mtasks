class HourglassNotifyLinkDestroyedJob < ApplicationJob
  queue_as :default

  retry_on Hourglass::ApiClient::Error, wait: :exponentially_longer, attempts: 3

  def perform(payload)
    integration = HourglassIntegration.find_by(id: payload[:integration_id] || payload['integration_id'])
    return unless integration&.active?

    channel_id = payload[:channel_id] || payload['channel_id']
    mtasks_project_id = payload[:project_id] || payload['project_id']

    client = Hourglass::ApiClient.for_integration(integration)
    client.notify_link_destroyed(channel_id: channel_id, mtasks_project_id: mtasks_project_id)
  rescue Hourglass::ApiClient::Unauthorized, Hourglass::ApiClient::NotFound => e
    Rails.logger.warn("HourglassNotifyLinkDestroyedJob swallowing #{e.class}: #{e.message}")
  end
end
