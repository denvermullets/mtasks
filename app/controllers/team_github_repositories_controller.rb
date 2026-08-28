class TeamGithubRepositoriesController < ApplicationController
  before_action :set_team
  before_action :authorize_team_member!

  def index
    @installation = @team.workspace.github_installation
    @subscribed_repos = @team.github_repository_subscriptions.active.includes(:pr_automation_rules)
    @lanes = @team.lanes
    @available_repos = fetch_available_repos if @installation
  end

  def create
    GhIntegration::SubscribeTeamToRepository.call(
      team: @team,
      repo_full_name: params[:repo_full_name]
    )

    redirect_to team_github_repositories_path(@team),
                notice: 'Repository added!'
  rescue GhIntegration::SubscribeTeamToRepository::SetupError => e
    redirect_to team_github_repositories_path(@team),
                alert: "Failed to add repository: #{e.message}"
  end

  def update
    subscription = @team.github_repository_subscriptions.find(params[:id])
    save_automation_rules(subscription, params[:automation_rules] || {})

    redirect_to team_github_repositories_path(@team),
                notice: 'Automation rules updated!'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to team_github_repositories_path(@team),
                alert: "Failed to save rules: #{e.message}"
  end

  def destroy
    subscription = @team.github_repository_subscriptions.find(params[:id])
    subscription.destroy

    redirect_to team_github_repositories_path(@team),
                notice: 'Repository removed'
  end

  private

  def save_automation_rules(subscription, rules_params)
    PrAutomationRule.transaction do
      subscription.pr_automation_rules.destroy_all
      create_simple_rule(subscription, 'pr_opened', rules_params[:pr_opened_lane_id])
      create_simple_rule(subscription, 'pr_closed', rules_params[:pr_closed_lane_id])
      create_merge_rules(subscription, rules_params[:merge_rules])
    end
  end

  def create_simple_rule(subscription, trigger, lane_id)
    return if lane_id.blank?

    subscription.pr_automation_rules.create!(trigger: trigger, lane_id: lane_id)
  end

  def create_merge_rules(subscription, merge_rules)
    Array(merge_rules).each do |rule|
      next if rule[:branch_pattern].blank? || rule[:lane_id].blank?

      subscription.pr_automation_rules.create!(
        trigger: 'pr_merged',
        branch_pattern: rule[:branch_pattern].strip,
        lane_id: rule[:lane_id]
      )
    end
  end

  def set_team
    @team = Team.find(params[:team_id])
  end

  def authorize_team_member!
    return if @team.users.include?(current_user)

    redirect_to root_path, alert: 'Access denied'
  end

  def fetch_available_repos
    installation = @team.workspace.github_installation
    return [] unless installation

    all_repos = GhIntegration::FetchInstallationRepositories.call(
      installation_id: installation.installation_id
    )

    # Filter out already subscribed repos
    subscribed_repo_names = @subscribed_repos.pluck(:github_repo_full_name)
    all_repos.reject { |repo| subscribed_repo_names.include?(repo[:full_name]) }
  rescue StandardError => e
    Rails.logger.error("Failed to fetch repos: #{e.message}")
    []
  end
end
