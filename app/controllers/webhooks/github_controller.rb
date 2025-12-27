module Webhooks
  class GithubController < ApplicationController
    include GithubWebhookVerification

    skip_before_action :verify_authenticity_token
    skip_before_action :require_authentication
    skip_before_action :set_current_team
    before_action :verify_github_signature

    def create
      event_type = request.headers['X-GitHub-Event']

      case event_type
      when 'pull_request'
        handle_pull_request_event
      when 'issue_comment'
        handle_issue_comment_event
      when 'ping'
        handle_ping_event
      when 'installation', 'installation_repositories'
        handle_installation_event
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

      # Find ALL matching subscriptions based on shortcodes in PR
      subscriptions = find_subscriptions_for_webhook(pr_data)

      if subscriptions.empty?
        Rails.logger.info("No matching subscriptions for PR ##{pr_data['number']}")
        return
      end

      # Update installation timestamp
      installation = GithubInstallation.find_by(
        installation_id: webhook_payload.dig('installation', 'id')
      )
      installation&.update(last_webhook_at: Time.current)

      # Queue job for EACH team whose shortcode was mentioned
      subscriptions.each do |subscription|
        subscription.update(last_webhook_at: Time.current)
        GithubWebhookProcessorJob.perform_later(subscription.id, pr_data.to_json)

        Rails.logger.info(
          "Processing PR ##{pr_data['number']} for team #{subscription.team.identifier}"
        )
      end
    end

    def handle_issue_comment_event
      action = webhook_payload['action']
      comment = webhook_payload['comment']
      issue = webhook_payload['issue']

      return unless valid_pr_comment?(action, issue)

      # For comments, we need to find subscriptions based on the PR data
      pr_data = issue # Issue contains PR data for PR comments
      subscriptions = find_subscriptions_for_webhook(pr_data)

      subscriptions.each do |subscription|
        queue_comment_processing(subscription, issue, comment)
      end
    end

    def handle_ping_event
      Rails.logger.info("Received GitHub ping event for repo: #{webhook_payload.dig('repository', 'full_name')}")
    end

    def handle_installation_event
      installation_id = webhook_payload.dig('installation', 'id')&.to_s
      action = webhook_payload['action']

      Rails.logger.info("Received installation event: #{action} for installation #{installation_id}")

      case action
      when 'created', 'added'
        handle_repositories_added(installation_id)
      when 'removed'
        handle_repositories_removed(installation_id)
      when 'deleted'
        # Installation was completely deleted - cascade deletes subscriptions
        installation = GithubInstallation.find_by(installation_id: installation_id)
        installation&.destroy
        Rails.logger.info("Deleted installation #{installation_id} and all subscriptions")
      else
        # For other actions, just update the last_webhook_at timestamp
        installation = GithubInstallation.find_by(installation_id: installation_id)
        if installation
          installation.update(last_webhook_at: Time.current)
          Rails.logger.info("Updated installation #{installation_id}")
        end
      end
    end

    def handle_repositories_added(installation_id)
      repositories = webhook_payload['repositories_added'] || []
      GhIntegration::ProcessAddedRepositories.call(
        installation_id: installation_id,
        repositories: repositories
      )
    end

    def handle_repositories_removed(installation_id)
      repositories = webhook_payload['repositories_removed'] || []
      GhIntegration::ProcessRemovedRepositories.call(
        installation_id: installation_id,
        repositories: repositories
      )
    end

    def valid_pr_comment?(action, issue)
      return false unless issue&.dig('pull_request')
      return false unless action == 'created'

      true
    end

    def find_subscriptions_for_webhook(pr_data)
      GhIntegration::FindFromWebhook.call(
        installation_id: webhook_payload.dig('installation', 'id'),
        repo_full_name: webhook_payload.dig('repository', 'full_name'),
        pr_data: pr_data
      )
    end

    def queue_comment_processing(subscription, issue, comment)
      GithubCommentProcessorJob.perform_later(
        subscription.id,
        issue['number'],
        comment['body']
      )

      repo_full_name = webhook_payload.dig('repository', 'full_name')
      Rails.logger.info("Queued comment processing for PR ##{issue['number']} in #{repo_full_name}")
    end
  end
end
