module GhIntegration
  class ProcessRemovedRepositories < Service
    def initialize(installation_id:, repositories:, delivery_id: nil)
      @installation_id = installation_id
      @repositories = repositories
      @delivery_id = delivery_id
    end

    def call
      return if @repositories.empty?

      removed = @repositories.sum { |repo| remove_integrations(repo) }
      track_subscriptions_removed(removed)
    end

    private

    def track_subscriptions_removed(count)
      return unless count.positive?

      Vektis::EventEmitter.integration(
        'github-integration', 'unlink',
        provider: 'github', via: 'webhook',
        key: [@delivery_id, @installation_id],
        properties: { count: count, webhook_event: 'installation_repositories.removed' }
      )
    end

    # Returns how many subscriptions this repo removal actually destroyed.
    def remove_integrations(repo)
      repo_full_name = repo['full_name']

      # Find installation
      installation = GithubInstallation.find_by(installation_id: @installation_id)
      return 0 unless installation

      # Find and delete all subscriptions for this installation + repo
      # (could be multiple teams subscribed to the same repo)
      subscriptions = GithubRepositorySubscription.where(
        github_installation: installation,
        github_repo_full_name: repo_full_name
      )

      count = subscriptions.count
      subscriptions.destroy_all
      Rails.logger.info("Deleted #{count} subscription(s) for repo #{repo_full_name}")
      count
    end
  end
end
