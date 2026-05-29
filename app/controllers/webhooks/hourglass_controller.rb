module Webhooks
  class HourglassController < ApplicationController
    include HourglassWebhookVerification

    skip_before_action :verify_authenticity_token
    skip_before_action :require_authentication
    skip_before_action :set_current_team
    before_action :verify_hourglass_signature

    def create
      event_type = request.headers['X-Hourglass-Event'].to_s
      delivery_id = request.headers['X-Hourglass-Delivery'].to_s

      if event_type.blank? || delivery_id.blank?
        Rails.logger.warn('Hourglass webhook missing event/delivery headers')
        head :bad_request
        return
      end

      delivery = WebhookDelivery.find_or_initialize_by(source: 'hourglass', delivery_id: delivery_id)
      if delivery.persisted?
        Rails.logger.info("Hourglass webhook duplicate delivery #{delivery_id}; skipping")
        head :ok
        return
      end

      record_and_enqueue(delivery, event_type)
      head :ok
    end

    private

    def record_and_enqueue(delivery, event_type)
      delivery.assign_attributes(event_type: event_type, received_at: Time.current, payload: webhook_payload)
      delivery.save!
      @integration.update(last_webhook_at: Time.current)
      HourglassWebhookProcessorJob.perform_later(@integration.id, delivery.id)
    end
  end
end
