class GithubIntegrationsController < ApplicationController
  before_action :set_team, except: %i[callback failure]
  before_action :authorize_team_member!, except: %i[callback failure]

  def show
    @integration = @team.github_integration
  end

  def new
    # Store team_id in session for OAuth callback
    session[:github_oauth_team_id] = @team.id
    redirect_to '/auth/github', allow_other_host: true
  end

  def callback
    auth = request.env['omniauth.auth']
    team_id = session.delete(:github_oauth_team_id)

    unless team_id
      redirect_to root_path, alert: 'OAuth session expired. Please try again.'
      return
    end

    @team = current_user.teams.find_by(id: team_id)
    unless @team
      redirect_to root_path, alert: 'Team not found.'
      return
    end

    # Create or update GitHub integration
    integration = @team.github_integration || @team.build_github_integration

    integration.assign_attributes(
      access_token: auth.credentials.token,
      github_repo_full_name: extract_repo_name(auth),
      active: true,
      token_expires_at: auth.credentials.expires_at ? Time.at(auth.credentials.expires_at) : nil
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
  end

  def failure
    redirect_to root_path, alert: 'GitHub authentication failed. Please try again.'
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

  def extract_repo_name(auth)
    # Try to get repo from OAuth params if available
    # This may need adjustment based on your OAuth flow
    # For now, returning nil - user will need to provide it separately or we extract from webhook
    auth.extra&.raw_info&.login
  end
end
