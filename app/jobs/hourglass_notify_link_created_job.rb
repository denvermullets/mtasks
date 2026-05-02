class HourglassNotifyLinkCreatedJob < ApplicationJob
  queue_as :default

  retry_on Hourglass::ApiClient::Error, wait: :exponentially_longer, attempts: 3

  def perform(link_id)
    link = HourglassLink.find_by(id: link_id)
    return unless link

    integration = link.hourglass_integration
    return unless integration&.active?

    client = Hourglass::ApiClient.for_integration(integration)
    client.notify_link_created(channel_id: link.hourglass_channel_id, project: link.mtasks_project)
  rescue Hourglass::ApiClient::Unauthorized, Hourglass::ApiClient::NotFound => e
    Rails.logger.warn("HourglassNotifyLinkCreatedJob marking link #{link_id} broken: #{e.message}")
    link&.update(status: 'broken')
  end
end
