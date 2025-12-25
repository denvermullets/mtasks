class GithubIntegrationsController < ApplicationController
  before_action :set_team, except: %i[callback]
  before_action :authorize_team_member!, except: %i[callback]

  def show
    @integration = @team.github_integration
  end

  def new
    # Store team_id in session for installation callback
    session[:github_installation_team_id] = @team.id

    # Redirect to GitHub App installation page
    app_slug = ENV.fetch('GITHUB_APP_SLUG', 'your-app-name')
    redirect_to "https://github.com/apps/#{app_slug}/installations/new", allow_other_host: true
  end

  def callback
    installation_id = params[:installation_id]
    team_id = session.delete(:github_installation_team_id)

    return unless valid_callback_params?(installation_id, team_id)

    GithubIntegration::Setup.call(team: @team, installation_id: installation_id)
    redirect_to team_github_integration_path(@team), notice: 'Successfully connected to GitHub!'
  rescue GithubIntegration::Setup::SetupError => e
    redirect_to team_github_integration_path(@team), alert: e.message
  rescue Octokit::Error => e
    Rails.logger.error("GitHub API error: #{e.message}")
    redirect_to team_github_integration_path(@team), alert: "GitHub error: #{e.message}"
  end

  def destroy
    @integration = @team.github_integration

    if @integration&.destroy
      redirect_to team_github_integration_path(@team), notice: 'GitHub integration disconnected.'
    else
      redirect_to team_github_integration_path(@team), alert: 'Failed to disconnect integration.'
    end
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
    authorize_team_access!(@team)
  end

  def authorize_team_member!
    return if @team.users.include?(current_user)

    redirect_to root_path, alert: "You don't have permission to manage this team's integrations."
  end

  def valid_callback_params?(installation_id, team_id)
    unless installation_id
      redirect_to root_path, alert: 'Installation ID missing. Please try again.'
      return false
    end

    unless team_id
      redirect_to root_path, alert: 'Session expired. Please try again.'
      return false
    end

    @team = current_user.teams.find_by(id: team_id)
    unless @team
      redirect_to root_path, alert: 'Team not found.'
      return false
    end

    true
  end
end
