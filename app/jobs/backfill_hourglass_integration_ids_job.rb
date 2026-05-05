class BackfillHourglassIntegrationIdsJob < ApplicationJob
  queue_as :default

  def perform
    HourglassIntegration.find_each do |integration|
      backfill_one(integration)
    end
  end

  private

  def backfill_one(integration)
    me = Hourglass::ApiClient.for_integration(integration).verify_token
    payload = me.is_a?(Hash) ? (me['integration'] || {}) : {}
    updates = {}
    updates[:hourglass_integration_id] = payload['id'] if payload['id']
    updates[:webhook_secret] = payload['webhook_secret'] if payload['webhook_secret'].present?
    if updates.empty?
      Rails.logger.info("BackfillHourglassIntegrationIdsJob #{integration.id}: /me lacks integration data")
      return
    end

    integration.update!(updates)
  rescue Hourglass::ApiClient::Error => e
    Rails.logger.warn("BackfillHourglassIntegrationIdsJob #{integration.id} failed: #{e.message}")
  end
end
