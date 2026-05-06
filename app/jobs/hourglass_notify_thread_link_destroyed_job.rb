class HourglassNotifyThreadLinkDestroyedJob < ApplicationJob
  queue_as :default

  retry_on Hourglass::ApiClient::Error, wait: :exponentially_longer, attempts: 3

  def perform(payload)
    integration = HourglassIntegration.find_by(id: fetch(payload, :integration_id))
    return unless integration&.active?

    Hourglass::WebhookDispatcher.call(
      integration: integration,
      event_type: 'link.removed',
      data: {
        link_type: 'issue_thread',
        mtasks_team_id: fetch(payload, :mtasks_team_id),
        mtasks_issue_id: fetch(payload, :mtasks_issue_id),
        hourglass_thread_id: fetch(payload, :hourglass_thread_id)
      }
    )
  rescue Hourglass::ApiClient::NotFound, Hourglass::ApiClient::Unauthorized => e
    Rails.logger.warn("HourglassNotifyThreadLinkDestroyedJob #{payload.inspect}: #{e.message}")
  end

  private

  def fetch(payload, key)
    payload[key] || payload[key.to_s]
  end
end
