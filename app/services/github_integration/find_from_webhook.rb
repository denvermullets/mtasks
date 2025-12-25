module GithubIntegration
  class FindFromWebhook < Service
    def initialize(installation_id:, repo_full_name:)
      @installation_id = installation_id
      @repo_full_name = repo_full_name
    end

    def call
      integration = GithubIntegration.find_by(
        installation_id: @installation_id,
        github_repo_full_name: @repo_full_name,
        active: true
      )

      unless integration
        Rails.logger.warn("No active integration found for installation: #{@installation_id}, repo: #{@repo_full_name}")
        return nil
      end

      integration
    end
  end
end
