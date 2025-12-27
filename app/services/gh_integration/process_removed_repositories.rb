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

      # Find and delete all integrations for this installation + repo
      # (could be multiple teams using the same installation)
      integrations = GithubIntegration.where(
        installation_id: @installation_id,
        github_repo_full_name: repo_full_name
      )

      count = integrations.count
      integrations.destroy_all
      Rails.logger.info("Deleted #{count} integration(s) for repo #{repo_full_name}")
    end
  end
end
