module GhIntegration
  class ProcessAddedRepositories < Service
    def initialize(installation_id:, repositories:)
      @installation_id = installation_id
      @repositories = repositories
    end

    def call
      return if @repositories.empty?

      # Find pending setup to determine which team initiated this
      pending_setup = PendingGithubSetup.active.find_by(installation_id: @installation_id)

      unless pending_setup
        Rails.logger.warn("No pending setup found for installation #{@installation_id}, cannot create integrations")
        return
      end

      team = pending_setup.team

      @repositories.each do |repo|
        create_or_update_integration(team, repo)
      end

      # Delete the pending setup now that we've processed it
      pending_setup.destroy
      Rails.logger.info("Deleted pending setup for installation #{@installation_id}")
    end

    private

    def create_or_update_integration(team, repo)
      repo_full_name = repo['full_name']

      # Create or update integration for this team + installation + repo
      integration = GithubIntegration.find_or_initialize_by(
        team: team,
        installation_id: @installation_id,
        github_repo_full_name: repo_full_name
      )

      integration.update!(
        active: true,
        last_webhook_at: Time.current
      )

      Rails.logger.info("Created/updated integration for #{team.name} - #{repo_full_name}")
    end
  end
end
