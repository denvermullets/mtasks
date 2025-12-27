class GithubIntegrationsController < ApplicationController
  before_action :set_team, except: %i[callback]
  before_action :authorize_team_member!, except: %i[callback]

  def show
    @integration = @team.github_integration
  end

  def new
    # Redirect to GitHub App installation page with setup URL and state
    app_slug = ENV.fetch('GITHUB_APP_SLUG', 'your-app-name')
    callback_url = github_callback_url

    # Encode team_id in state parameter so GitHub can pass it back
    state = Base64.urlsafe_encode64({ team_id: @team.id, timestamp: Time.current.to_i }.to_json)

    Rails.logger.info("Redirecting to GitHub for team #{@team.id} with callback URL: #{callback_url}")
    redirect_to "https://github.com/apps/#{app_slug}/installations/new?state=#{state}",
                allow_other_host: true
  end

  def callback
    installation_id = params[:installation_id]
    state = params[:state]

    log_callback_received(installation_id, state)

    team_id = extract_team_id_from_state(state)
    return unless valid_callback_params?(installation_id, team_id)

    setup_github_integration(installation_id)
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
      redirect_to root_path, alert: 'Invalid callback state. Please try again.'
      return false
    end

    @team = current_user.teams.find_by(id: team_id)
    unless @team
      redirect_to root_path, alert: 'Team not found or access denied.'
      return false
    end

    true
  end

  def extract_team_id_from_state(state)
    return nil unless state.present?

    decoded = JSON.parse(Base64.urlsafe_decode64(state))
    decoded['team_id']
  rescue StandardError => e
    Rails.logger.error("Failed to decode state parameter: #{e.message}")
    nil
  end

  def log_callback_received(installation_id, state)
    Rails.logger.info("GitHub callback received - installation_id: #{installation_id}, state: #{state}")
    Rails.logger.info("All params: #{params.inspect}")
  end

  def setup_github_integration(installation_id)
    # Create pending setup so webhooks can find which team initiated this installation
    PendingGithubSetup.create_for_team!(team: @team, installation_id: installation_id.to_s)
    Rails.logger.info("Created pending setup for team #{@team.id}, installation #{installation_id}")

    # Also create initial integration for immediate feedback
    # The webhook will handle creating integrations for all repos
    GhIntegration::Setup.call(team: @team, installation_id: installation_id)
    redirect_to team_github_integration_path(@team), notice: 'Successfully connected to GitHub!'
  rescue GhIntegration::Setup::SetupError => e
    handle_setup_error(e)
  rescue Octokit::Error => e
    handle_github_api_error(e)
  end

  def handle_setup_error(error)
    Rails.logger.error("Setup error: #{error.message}")
    redirect_to team_github_integration_path(@team), alert: error.message
  end

  def handle_github_api_error(error)
    Rails.logger.error("GitHub API error: #{error.message}")
    redirect_to team_github_integration_path(@team), alert: "GitHub error: #{error.message}"
  end
end
