module GhIntegration
  class ProcessInstallationEvent < Service
    def initialize(installation_id:, action:, webhook_payload:, delivery_id: nil)
      @installation_id = installation_id
      @action = action
      @webhook_payload = webhook_payload
      @delivery_id = delivery_id
    end

    def call
      case @action
      when 'created', 'added'
        handle_repositories_added
      when 'removed'
        handle_repositories_removed
      when 'deleted'
        handle_installation_deleted
      else
        update_installation_timestamp
      end
    end

    private

    def handle_repositories_added
      repositories = @webhook_payload['repositories_added'] || []
      GhIntegration::ProcessAddedRepositories.call(
        installation_id: @installation_id,
        repositories: repositories,
        delivery_id: @delivery_id
      )
    end

    def handle_repositories_removed
      repositories = @webhook_payload['repositories_removed'] || []
      GhIntegration::ProcessRemovedRepositories.call(
        installation_id: @installation_id,
        repositories: repositories,
        delivery_id: @delivery_id
      )
    end

    def handle_installation_deleted
      installation = GithubInstallation.find_by(installation_id: @installation_id)
      destroyed = installation&.destroy
      Rails.logger.info("Deleted installation #{@installation_id} and all subscriptions")
      return unless destroyed

      Vektis::EventEmitter.integration(
        'github-integration', 'unlink',
        provider: 'github', via: 'webhook',
        key: [@delivery_id, @installation_id],
        properties: { webhook_event: 'installation.deleted' }
      )
    end

    def update_installation_timestamp
      installation = GithubInstallation.find_by(installation_id: @installation_id)
      return unless installation

      installation.update(last_webhook_at: Time.current)
      Rails.logger.info("Updated installation #{@installation_id}")
    end
  end
end
