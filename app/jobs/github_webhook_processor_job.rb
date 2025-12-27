class GithubWebhookProcessorJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(subscription_id, pr_data_json)
    subscription = GithubRepositorySubscription.find_by(id: subscription_id)

    unless subscription
      Rails.logger.error("GithubRepositorySubscription #{subscription_id} not found")
      return
    end

    pr_data = JSON.parse(pr_data_json)

    sync_service = GithubPrSyncService.new(subscription)
    pr = sync_service.sync_pull_request(pr_data)

    if pr
      log_success(pr, subscription)
    else
      log_failure(pr_data, subscription)
    end
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse PR data JSON: #{e.message}")
  end

  private

  def log_success(pull_request, subscription)
    Rails.logger.info(
      "Successfully processed webhook for PR ##{pull_request.pr_number} " \
      "(team: #{subscription.team.identifier})"
    )
  end

  def log_failure(pr_data, subscription)
    Rails.logger.error(
      "Failed to sync PR ##{pr_data['number']} for team #{subscription.team.identifier}"
    )
  end
end
