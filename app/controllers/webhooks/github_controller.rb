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

      integration = find_integration_for_webhook
      return unless integration

      # Update last webhook timestamp
      integration.update(last_webhook_at: Time.current)

      # Queue background job to process the webhook
      GithubWebhookProcessorJob.perform_later(integration.id, pr_data.to_json)

      repo_full_name = webhook_payload.dig('repository', 'full_name')
      Rails.logger.info("Queued webhook processing for PR ##{pr_data['number']} in #{repo_full_name}")
    end

    def handle_issue_comment_event
      action = webhook_payload['action']
      comment = webhook_payload['comment']
      issue = webhook_payload['issue']

      return unless valid_pr_comment?(action, issue)

      integration = find_integration_for_webhook
      return unless integration

      queue_comment_processing(integration, issue, comment)
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
        # Installation was completely deleted - remove all integrations for this installation
        GithubIntegration.where(installation_id: installation_id).destroy_all
        Rails.logger.info("Deleted all integrations for installation #{installation_id}")
      else
        # For other actions, just update the last_webhook_at timestamp
        if installation_id && GithubIntegration.exists?(installation_id: installation_id)
          GithubIntegration.where(installation_id: installation_id).update_all(last_webhook_at: Time.current)
          Rails.logger.info("Updated existing integrations for installation #{installation_id}")
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

    def find_integration_for_webhook
      GhIntegration::FindFromWebhook.call(
        installation_id: webhook_payload.dig('installation', 'id'),
        repo_full_name: webhook_payload.dig('repository', 'full_name')
      )
    end

    def queue_comment_processing(integration, issue, comment)
      GithubCommentProcessorJob.perform_later(
        integration.id,
        issue['number'],
        comment['body']
      )

      repo_full_name = webhook_payload.dig('repository', 'full_name')
      Rails.logger.info("Queued comment processing for PR ##{issue['number']} in #{repo_full_name}")
    end
  end
end
