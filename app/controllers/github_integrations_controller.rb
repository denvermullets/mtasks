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
    # GitHub App installation callback
    installation_id = params[:installation_id]
    setup_action = params[:setup_action]
    team_id = session.delete(:github_installation_team_id)

    unless installation_id
      redirect_to root_path, alert: 'Installation ID missing. Please try again.'
      return
    end

    unless team_id
      redirect_to root_path, alert: 'Session expired. Please try again.'
      return
    end

    @team = current_user.teams.find_by(id: team_id)
    unless @team
      redirect_to root_path, alert: 'Team not found.'
      return
    end

    # Get installation details from GitHub
    begin
      client = Octokit::Client.new(bearer_token: GithubApp.generate_jwt)
      installation = client.find_app_installations.find { |i| i[:id] == installation_id.to_i }

      unless installation
        redirect_to team_github_integration_path(@team), alert: 'Installation not found.'
        return
      end

      # Get repositories this installation has access to
      token = GithubApp.installation_token(installation_id)
      repos_client = Octokit::Client.new(access_token: token)
      repos = repos_client.list_app_installation_repositories[:repositories]

      # Use the first repo (or you could show a selection UI)
      repo = repos.first
      unless repo
        redirect_to team_github_integration_path(@team), alert: 'No repositories found for this installation.'
        return
      end

      # Create or update GitHub integration
      integration = @team.github_integration || @team.build_github_integration

      integration.assign_attributes(
        installation_id: installation_id,
        github_repo_full_name: repo[:full_name],
        active: true
      )

      if integration.save
        # Create webhook via GitHub API
        begin
          GithubApiClient.new(integration).create_webhook
          redirect_to team_github_integration_path(@team), notice: 'Successfully connected to GitHub!'
        rescue StandardError => e
          Rails.logger.error("Failed to create webhook: #{e.message}")
          redirect_to team_github_integration_path(@team),
                      alert: "Connected but failed to create webhook: #{e.message}"
        end
      else
        redirect_to team_github_integration_path(@team),
                    alert: "Failed to save integration: #{integration.errors.full_messages.join(', ')}"
      end
    rescue Octokit::Error => e
      Rails.logger.error("GitHub API error: #{e.message}")
      redirect_to team_github_integration_path(@team), alert: "GitHub error: #{e.message}"
    end
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
end
