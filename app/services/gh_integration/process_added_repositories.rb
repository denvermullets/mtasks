module GhIntegration
  class ProcessAddedRepositories < Service
    def initialize(installation_id:, repositories:, delivery_id: nil)
      @installation_id = installation_id
      @repositories = repositories
      @delivery_id = delivery_id
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
      created = @repositories.sum do |repo|
        workspace.teams.count { |team| create_subscription(team, installation, repo).previously_new_record? }
      end
      track_subscriptions_created(created)

      # Delete the pending setup now that we've processed it
      pending_setup.destroy
      Rails.logger.info("Deleted pending setup for installation #{@installation_id}")
    end

    private

    # One event for the whole installation event, not one per repo per team: adding an app to a
    # workspace is one gesture, and `count` is the registered way to say how big it was (§5.2).
    # Repository names are banned from properties for the same reason lane names are (§5.2).
    def track_subscriptions_created(count)
      return unless count.positive?

      Vektis::EventEmitter.integration(
        'github-integration', 'link',
        provider: 'github', via: 'webhook',
        key: [@delivery_id, @installation_id],
        properties: { count: count, webhook_event: 'installation_repositories.added' }
      )
    end

    # Returns the subscription so the caller can count actual additions rather than attempts —
    # re-running an installation event must not inflate the link count.
    def create_subscription(team, installation, repo)
      repo_full_name = repo['full_name']

      # Create or update subscription for this team + installation + repo
      subscription = GithubRepositorySubscription.find_or_create_by!(
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
      subscription
    end
  end
end
