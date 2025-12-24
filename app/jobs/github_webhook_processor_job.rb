class GithubWebhookProcessorJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(integration_id, pr_data_json)
    integration = GithubIntegration.find_by(id: integration_id)

    unless integration
      Rails.logger.error("GithubIntegration #{integration_id} not found")
      return
    end

    pr_data = JSON.parse(pr_data_json)

    sync_service = GithubPrSyncService.new(integration)
    pr = sync_service.sync_pull_request(pr_data)

    if pr
      Rails.logger.info("Successfully processed webhook for PR ##{pr.pr_number}")
    else
      Rails.logger.error("Failed to sync PR ##{pr_data['number']}")
    end
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse PR data JSON: #{e.message}")
  end
end
