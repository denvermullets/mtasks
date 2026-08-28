class GithubCommentProcessorJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(subscription_id, pr_number, comment_body)
    subscription = GithubRepositorySubscription.find_by(id: subscription_id)

    unless subscription
      Rails.logger.error("GithubRepositorySubscription #{subscription_id} not found")
      return
    end

    pull_request = find_or_fetch_pull_request(subscription, pr_number)
    return unless pull_request

    GithubPrSyncService.new(subscription).link_issues_from_text(pull_request, comment_body)
  end

  private

  def find_or_fetch_pull_request(subscription, pr_number)
    pull_request = subscription.pull_requests.find_by(pr_number: pr_number)
    return pull_request if pull_request

    fetch_pull_request_from_github(subscription, pr_number)
  end

  def fetch_pull_request_from_github(subscription, pr_number)
    Rails.logger.info("PR ##{pr_number} not found locally, fetching from GitHub")

    client = Octokit::Client.new(access_token: subscription.access_token)
    pr_data = client.pull_request(subscription.github_repo_full_name, pr_number)

    sync_service = GithubPrSyncService.new(subscription)
    # Octokit hands back symbol keys; the sync service reads string keys.
    sync_service.sync_pull_request(pr_data.to_h.deep_stringify_keys)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch PR ##{pr_number}: #{e.message}")
    nil
  end
end
