class HourglassWebhookProcessorJob < ApplicationJob
  HANDLED_EVENTS = %w[
    message.created
    message.updated
    message.deleted
    channel.created
    channel.updated
    channel.deleted
    ping
  ].freeze

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
    if HANDLED_EVENTS.include?(delivery.event_type)
      log_event(delivery.event_type, delivery, integration)
    else
      Rails.logger.info(
        "Hourglass webhook unhandled event #{delivery.event_type} (delivery=#{delivery.delivery_id})"
      )
    end
  end

  def log_event(event_type, delivery, integration)
    Rails.logger.info(
      "Hourglass #{event_type} delivery=#{delivery.delivery_id} integration=#{integration.id}"
    )
  end
end
