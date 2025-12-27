module GhIntegration
  class FetchInstallationRepositories < Service
    def initialize(installation_id:)
      @installation_id = installation_id
    end

    def call
      token = GithubApp.installation_token(@installation_id)
      client = Octokit::Client.new(access_token: token)

      response = client.list_app_installation_repositories
      response[:repositories].map do |repo|
        {
          id: repo[:id],
          full_name: repo[:full_name],
          name: repo[:name],
          owner: repo[:owner][:login],
          private: repo[:private],
          html_url: repo[:html_url]
        }
      end
    rescue Octokit::Error => e
      Rails.logger.error("Failed to fetch repositories for installation #{@installation_id}: #{e.message}")
      []
    end
  end
end
