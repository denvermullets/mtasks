module GithubIntegration
  class Setup < Service
    class SetupError < StandardError; end

    def initialize(team:, installation_id:)
      @team = team
      @installation_id = installation_id
    end

    def call
      fetch_github_installation
      repo = fetch_first_repository
      create_integration_with_webhook(repo)
    end

    private

    def fetch_github_installation
      client = Octokit::Client.new(bearer_token: GithubApp.generate_jwt)
      installation = client.find_app_installations.find { |i| i[:id] == @installation_id.to_i }

      raise SetupError, 'Installation not found.' unless installation

      installation
    end

    def fetch_first_repository
      token = GithubApp.installation_token(@installation_id)
      repos_client = Octokit::Client.new(access_token: token)
      repos = repos_client.list_app_installation_repositories[:repositories]
      repo = repos.first

      raise SetupError, 'No repositories found for this installation.' unless repo

      repo
    end

    def create_integration_with_webhook(repo)
      integration = @team.github_integration || @team.build_github_integration
      integration.assign_attributes(
        installation_id: @installation_id,
        github_repo_full_name: repo[:full_name],
        active: true
      )

      unless integration.save
        raise SetupError, "Failed to save integration: #{integration.errors.full_messages.join(', ')}"
      end

      create_webhook_for_integration(integration)
      integration
    end

    def create_webhook_for_integration(integration)
      GithubApiClient.new(integration).create_webhook
    rescue StandardError => e
      Rails.logger.error("Failed to create webhook: #{e.message}")
      raise SetupError, "Connected but failed to create webhook: #{e.message}"
    end
  end
end
