module GhIntegration
  class ProcessRemovedRepositories < Service
    def initialize(installation_id:, repositories:)
      @installation_id = installation_id
      @repositories = repositories
    end

    def call
      return if @repositories.empty?

      @repositories.each do |repo|
        remove_integrations(repo)
      end
    end

    private

    def remove_integrations(repo)
      repo_full_name = repo['full_name']

      # Find installation
      installation = GithubInstallation.find_by(installation_id: @installation_id)
      return unless installation

      # Find and delete all subscriptions for this installation + repo
      # (could be multiple teams subscribed to the same repo)
      subscriptions = GithubRepositorySubscription.where(
        github_installation: installation,
        github_repo_full_name: repo_full_name
      )

      count = subscriptions.count
      subscriptions.destroy_all
      Rails.logger.info("Deleted #{count} subscription(s) for repo #{repo_full_name}")
    end
  end
end
