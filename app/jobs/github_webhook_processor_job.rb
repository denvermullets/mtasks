class GithubWebhookProcessorJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Mirrors Webhooks::GithubController#processable_action? — the deliveries that reach this job.
  # Kept in sync by test/jobs/github_webhook_processor_job_test.rb.
  PR_WEBHOOK_ACTIONS = %w[opened edited synchronize closed reopened].freeze

  def perform(subscription_id, pr_data_json, action = nil, delivery_id = nil)
    subscription = GithubRepositorySubscription.find_by(id: subscription_id)

    unless subscription
      Rails.logger.error("GithubRepositorySubscription #{subscription_id} not found")
      return
    end

    pr_data = JSON.parse(pr_data_json)

    sync_service = GithubPrSyncService.new(subscription, delivery_id: delivery_id)
    pr = sync_service.sync_pull_request(pr_data, action: action)

    if pr
      log_success(pr, subscription)
      track_sync(subscription, pr, action, delivery_id)
    else
      log_failure(pr_data, subscription)
    end
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse PR data JSON: #{e.message}")
  end

  private

  # Emitted here rather than in the controller because taxonomy §4.5 counts *processed* deliveries:
  # a delivery that matched no subscription, or whose PR failed to save, is not integration usage.
  # The subscription joins the idempotency key — one PR can be watched by several teams, and each
  # of those is a separate team using the integration.
  def track_sync(subscription, pull_request, action, delivery_id)
    Vektis::EventEmitter.integration(
      'github-integration', 'sync',
      provider: 'github', via: 'webhook',
      key: [delivery_id, subscription.id],
      properties: { webhook_event: webhook_event(pull_request, action) }.compact
    )
  end

  # A closed, low-cardinality set (§5.2) — never a raw payload field. `merged` is worth separating
  # from `closed`: it is the action PR automation keys off, and the two have opposite meanings.
  #
  # The allowlist is checked here and not only in Webhooks::GithubController#processable_action?,
  # which already filters deliveries upstream (VEK-587). `action` originates in the GitHub payload
  # and perform is public — a future caller, a replay script or a new controller path would
  # otherwise interpolate an attacker-influenced string straight into properties, where vanalytics
  # stores it verbatim with no delete path. An unrecognized action drops the property rather than
  # the event: track_sync compacts, so the delivery is still counted as integration usage.
  def webhook_event(pull_request, action)
    return nil if action.blank?
    return 'pull_request.merged' if action == 'closed' && pull_request.merged?
    return nil unless PR_WEBHOOK_ACTIONS.include?(action)

    "pull_request.#{action}"
  end

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
