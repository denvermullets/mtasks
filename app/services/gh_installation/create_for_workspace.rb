module GhInstallation
  class CreateForWorkspace < Service
    class SetupError < StandardError; end

    def initialize(workspace:, installation_id:)
      @workspace = workspace
      @installation_id = installation_id
    end

    def call
      # Fetch installation metadata from GitHub API
      installation_data = fetch_installation_data

      raise SetupError, 'Installation not found' unless installation_data

      # Create or update installation record
      installation = @workspace.github_installations
                               .find_or_initialize_by(installation_id: @installation_id)

      installation.update!(
        github_account_login: installation_data[:account][:login],
        github_account_type: installation_data[:account][:type],
        active: true
      )

      Rails.logger.info(
        "Created GitHub installation #{@installation_id} for workspace #{@workspace.id}"
      )

      installation
    end

    private

    def fetch_installation_data
      client = Octokit::Client.new(bearer_token: GithubApp.generate_jwt)
      client.find_app_installations
            .find { |i| i[:id] == @installation_id.to_i }
    rescue Octokit::Error => e
      Rails.logger.error("Failed to fetch installation #{@installation_id}: #{e.message}")
      nil
    end
  end
end
