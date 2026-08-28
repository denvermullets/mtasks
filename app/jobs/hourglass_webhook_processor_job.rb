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

    team = dispatch(delivery, integration)

    delivery.update!(processed_at: Time.current)
    track_sync(delivery, integration, team) if team
  end

  private

  # Taxonomy §4.5 counts *successfully processed* deliveries. The early return above is the app's
  # own dedupe — the ticket's instruction is to reuse it rather than add a second — and the
  # deterministic event_id is the second layer, for a redelivery that arrives before the first is
  # marked processed.
  #
  # Channel events and unrecognised event types are deliberately not counted: they are received,
  # not acted on, and a `sync` that fired for a ping would make the integration look busier than
  # it is.
  #
  # The team comes from the handler rather than the integration: HourglassIntegration belongs to a
  # workspace and serves every team in it, so it is not a tenant. A delivery that touched no
  # team-scoped record has nobody to bill and emits nothing.
  def track_sync(delivery, integration, team)
    Vektis::EventEmitter.integration(
      'hourglass-integration', 'sync', team: team,
                                       provider: 'hourglass', via: 'webhook',
                                       key: [delivery.delivery_id, integration.id],
                                       properties: { webhook_event: delivery.event_type }
    )
  end

  # Returns the team whose record the handler acted on, or nil when nothing ran, the handler
  # raised, or it touched nothing team-scoped. A handler that raised is not processing.
  def dispatch(delivery, integration)
    handler_class = MESSAGE_HANDLERS[delivery.event_type] || LINK_HANDLERS[delivery.event_type]
    return run_handler(handler_class, delivery, integration) if handler_class

    if CHANNEL_EVENTS.include?(delivery.event_type)
      log_event(delivery.event_type, delivery, integration)
    else
      Rails.logger.info(
        "Hourglass webhook unhandled event #{delivery.event_type} (delivery=#{delivery.delivery_id})"
      )
    end
    nil
  end

  # Built and called directly rather than through Service.call, which returns the handler's own
  # return value and so cannot hand back the team it acted on.
  def run_handler(handler_class, delivery, integration)
    handler = handler_class.new(delivery, integration)
    handler.call
    handler.tracked_team
  rescue StandardError => e
    Rails.logger.error(
      "HourglassWebhookProcessorJob handler #{handler_class} raised " \
      "for delivery=#{delivery.delivery_id}: #{e.class}: #{e.message}"
    )
    nil
  end

  def log_event(event_type, delivery, integration)
    Rails.logger.info(
      "Hourglass #{event_type} delivery=#{delivery.delivery_id} integration=#{integration.id}"
    )
  end
end
