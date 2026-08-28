module GhIntegration
  class ProcessAddedRepositories < Service
    def initialize(installation_id:, repositories:)
      @installation_id = installation_id
      @repositories = repositories
    end

    def call
      return if @repositories.empty?

      # Find pending setup to determine which workspace initiated this
      pending_setup = PendingGithubSetup.active.find_by(installation_id: @installation_id)

      unless pending_setup
        Rails.logger.warn("No pending setup found for installation #{@installation_id}, cannot create subscriptions")
        return
      end

      workspace = pending_setup.workspace
      installation = workspace.github_installations.find_by(installation_id: @installation_id)

      unless installation
        Rails.logger.error("Installation #{@installation_id} not found for workspace #{workspace.id}")
        return
      end

      # Create subscriptions for all teams in workspace (opt-out model)
      @repositories.each do |repo|
        workspace.teams.each do |team|
          create_subscription(team, installation, repo)
        end
      end

      # Delete the pending setup now that we've processed it
      pending_setup.destroy
      Rails.logger.info("Deleted pending setup for installation #{@installation_id}")
    end

    private

    def create_subscription(team, installation, repo)
      repo_full_name = repo['full_name']

      # Create or update subscription for this team + installation + repo
      GithubRepositorySubscription.find_or_create_by!(
        team: team,
        github_installation: installation,
        github_repo_full_name: repo_full_name
      ) do |sub|
        sub.active = true
        sub.last_webhook_at = Time.current
      end

      Rails.logger.info(
        "Created subscription for #{team.identifier} - #{repo_full_name}"
      )
    end
  end
end
