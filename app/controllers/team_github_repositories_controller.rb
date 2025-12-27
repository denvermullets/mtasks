class TeamGithubRepositoriesController < ApplicationController
  before_action :set_team
  before_action :authorize_team_member!

  def index
    @installation = @team.workspace.github_installation
    @subscribed_repos = @team.github_repository_subscriptions.active
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

  def destroy
    subscription = @team.github_repository_subscriptions.find(params[:id])
    subscription.destroy

    redirect_to team_github_repositories_path(@team),
                notice: 'Repository removed'
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def authorize_team_member!
    unless @team.users.include?(current_user)
      redirect_to root_path, alert: 'Access denied'
    end
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
  rescue => e
    Rails.logger.error("Failed to fetch repos: #{e.message}")
    []
  end
end
