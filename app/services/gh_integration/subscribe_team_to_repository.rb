module GhIntegration
  class SubscribeTeamToRepository < Service
    class SetupError < StandardError; end

    def initialize(team:, repo_full_name:)
      @team = team
      @repo_full_name = repo_full_name
    end

    def call
      installation = @team.workspace.github_installation
      raise SetupError, 'No GitHub installation found for workspace' unless installation

      # Verify repo is accessible via installation
      verify_repo_access(installation)

      # Create or reactivate subscription
      subscription = GithubRepositorySubscription.find_or_initialize_by(
        team: @team,
        github_installation: installation,
        github_repo_full_name: @repo_full_name
      )

      subscription.update!(active: true)

      Rails.logger.info(
        "Subscribed team #{@team.identifier} to repo #{@repo_full_name}"
      )

      subscription
    end

    private

    def verify_repo_access(installation)
      token = installation.access_token
      client = Octokit::Client.new(access_token: token)
      repos = client.list_app_installation_repositories[:repositories]

      unless repos.any? { |r| r[:full_name] == @repo_full_name }
        raise SetupError, "Repository #{@repo_full_name} not accessible via this installation"
      end
    rescue Octokit::Error => e
      Rails.logger.error("Failed to verify repo access: #{e.message}")
      raise SetupError, "Failed to verify repository access: #{e.message}"
    end
  end
end
