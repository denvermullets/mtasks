module Webhooks
  class GithubController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :require_authentication
    skip_before_action :set_current_team
    before_action :verify_github_signature

    def create
      event_type = request.headers['X-GitHub-Event']

      case event_type
      when 'pull_request'
        handle_pull_request_event
      when 'ping'
        handle_ping_event
      else
        Rails.logger.info("Received unhandled GitHub event: #{event_type}")
      end

      head :ok
    end

    private

    def handle_pull_request_event
      pr_data = webhook_payload['pull_request']
      action = webhook_payload['action']

      # Only process relevant actions
      return unless %w[opened edited synchronize closed reopened].include?(action)

      installation_id = webhook_payload.dig('installation', 'id')
      repo_full_name = webhook_payload.dig('repository', 'full_name')

      integration = GithubIntegration.find_by(
        installation_id: installation_id,
        github_repo_full_name: repo_full_name,
        active: true
      )

      unless integration
        Rails.logger.warn("No active integration found for installation: #{installation_id}, repo: #{repo_full_name}")
        return
      end

      # Update last webhook timestamp
      integration.update(last_webhook_at: Time.current)

      # Queue background job to process the webhook
      GithubWebhookProcessorJob.perform_later(integration.id, pr_data.to_json)

      Rails.logger.info("Queued webhook processing for PR ##{pr_data['number']} in #{repo_full_name}")
    end

    def handle_ping_event
      Rails.logger.info("Received GitHub ping event for repo: #{webhook_payload.dig('repository', 'full_name')}")
    end

    def verify_github_signature
      signature = request.headers['X-Hub-Signature-256']

      unless signature
        Rails.logger.warn('Missing GitHub webhook signature')
        head :unauthorized
        return
      end

      expected_signature = compute_signature(request.raw_post)

      return if Rack::Utils.secure_compare(signature, expected_signature)

      Rails.logger.warn('Invalid GitHub webhook signature')
      head :unauthorized
      nil
    end

    def compute_signature(payload_body)
      secret = ENV.fetch('GITHUB_WEBHOOK_SECRET', nil)
      "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, payload_body)}"
    end

    def webhook_payload
      @webhook_payload ||= JSON.parse(request.body.read)
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse GitHub webhook payload: #{e.message}")
      {}
    end
  end
end
