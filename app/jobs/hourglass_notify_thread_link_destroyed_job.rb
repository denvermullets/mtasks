class HourglassNotifyThreadLinkDestroyedJob < ApplicationJob
  queue_as :default

  retry_on Hourglass::ApiClient::Error, wait: :exponentially_longer, attempts: 3

  def perform(payload)
    integration = HourglassIntegration.find_by(id: payload[:integration_id] || payload['integration_id'])
    return unless integration&.active?

    Hourglass::WebhookDispatcher.call(
      integration: integration,
      event_type: 'link.removed',
      data: {
        link_type: 'issue_thread',
        mtasks_issue_id: payload[:mtasks_issue_id] || payload['mtasks_issue_id'],
        hourglass_thread_id: payload[:hourglass_thread_id] || payload['hourglass_thread_id']
      }
    )
  rescue Hourglass::ApiClient::NotFound, Hourglass::ApiClient::Unauthorized => e
    Rails.logger.warn("HourglassNotifyThreadLinkDestroyedJob #{payload.inspect}: #{e.message}")
  end
end
