class HourglassWebhookProcessorJob < ApplicationJob
  MESSAGE_HANDLERS = {
    'message.created' => HourglassWebhookProcessor::Message::CreatedHandler,
    'message.updated' => HourglassWebhookProcessor::Message::UpdatedHandler,
    'message.deleted' => HourglassWebhookProcessor::Message::DeletedHandler,
    'message.pinned' => HourglassWebhookProcessor::Message::PinnedHandler,
    'message.unpinned' => HourglassWebhookProcessor::Message::UnpinnedHandler
  }.freeze

  LINK_HANDLERS = {
    'link.created' => HourglassWebhookProcessor::Link::CreatedHandler,
    'link.removed' => HourglassWebhookProcessor::Link::RemovedHandler
  }.freeze

  CHANNEL_EVENTS = %w[channel.created channel.updated channel.deleted ping].freeze

  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(integration_id, delivery_id)
    integration = HourglassIntegration.find_by(id: integration_id)
    delivery = WebhookDelivery.find_by(id: delivery_id)

    unless integration && delivery
      Rails.logger.error(
        "HourglassWebhookProcessorJob missing record (integration=#{integration_id}, delivery=#{delivery_id})"
      )
      return
    end

    return if delivery.processed_at.present?

    dispatch(delivery, integration)

    delivery.update!(processed_at: Time.current)
  end

  private

  def dispatch(delivery, integration)
    handler_class = MESSAGE_HANDLERS[delivery.event_type] || LINK_HANDLERS[delivery.event_type]
    if handler_class
      run_handler(handler_class, delivery, integration)
    elsif CHANNEL_EVENTS.include?(delivery.event_type)
      log_event(delivery.event_type, delivery, integration)
    else
      Rails.logger.info(
        "Hourglass webhook unhandled event #{delivery.event_type} (delivery=#{delivery.delivery_id})"
      )
    end
  end

  def run_handler(handler_class, delivery, integration)
    handler_class.call(delivery, integration)
  rescue StandardError => e
    Rails.logger.error(
      "HourglassWebhookProcessorJob handler #{handler_class} raised " \
      "for delivery=#{delivery.delivery_id}: #{e.class}: #{e.message}"
    )
  end

  def log_event(event_type, delivery, integration)
    Rails.logger.info(
      "Hourglass #{event_type} delivery=#{delivery.delivery_id} integration=#{integration.id}"
    )
  end
end
