class Settings::HourglassIntegrationsController < ApplicationController
  before_action :set_workspace
  before_action :authorize_workspace_access!
  before_action :set_integration, only: %i[test_webhook destroy add_team remove_team]

  def show
    @integrations = @workspace.hourglass_integrations.active.includes(:subscribed_teams).order(:created_at)
    @manageable_teams = manageable_teams.order(:name)
  end

  def update
    teams = manageable_teams.where(id: Array(params[:team_ids])).to_a
    return redirect_with_alert('Pick at least one team to connect') if teams.empty?

    result = run_connect_service(teams)
    track_integration('hourglass-integration', 'link', provider: 'hourglass')
    stash_callback_token(result)
    redirect_to workspace_settings_hourglass_integration_path(@workspace), notice: connect_notice(result, teams)
  rescue Hourglass::ApiClient::Unauthorized
    redirect_with_alert('Invalid hourglass token')
  rescue Hourglass::ApiClient::Error => e
    Rails.logger.error("Hourglass connect failed: #{e.message}")
    redirect_with_alert("Failed to connect to Hourglass: #{e.message}")
  end

  def add_team
    team = manageable_teams.find_by(id: params[:team_id])
    return redirect_with_alert('Team not found') unless team

    HourglassIntegrations::SubscribeTeamsService.call(integration: @integration, teams: [team])
    redirect_to workspace_settings_hourglass_integration_path(@workspace),
                notice: "#{team.name} now uses #{server_label(@integration)}"
  end

  def remove_team
    team = manageable_teams.find_by(id: params[:team_id])
    return redirect_with_alert('Team not found') unless team

    HourglassIntegrations::UnsubscribeTeamService.call(integration: @integration, team: team)
    redirect_to workspace_settings_hourglass_integration_path(@workspace),
                notice: "#{team.name} removed from #{server_label(@integration)}"
  end

  def test_webhook
    result = run_test_webhook(@integration)
    if result.success?
      redirect_to workspace_settings_hourglass_integration_path(@workspace),
                  notice: "Test webhook delivered (#{result.delivery_id})"
    else
      redirect_with_alert("Test webhook failed: #{result.error}")
    end
  end

  # Disconnecting the server cuts off every subscribed team, so only someone who manages all of them
  # may do it; anyone else removes their own teams one at a time.
  def destroy
    unless (@integration.subscribed_teams.ids - manageable_teams.ids).empty?
      return redirect_with_alert('Only someone who manages every connected team can disconnect this server')
    end

    HourglassIntegrations::DisconnectService.new(@integration).call
    track_integration('hourglass-integration', 'unlink', provider: 'hourglass')
    redirect_to workspace_settings_hourglass_integration_path(@workspace), notice: 'Hourglass disconnected'
  end

  private

  def stash_callback_token(result)
    return if result.new_callback_token.blank?

    flash[:callback_token] = result.new_callback_token
    flash[:callback_token_integration_id] = result.integration.id
  end

  def connect_notice(result, teams)
    server = server_label(result.integration)
    names = teams.map(&:name).to_sentence
    return "Connected #{names} to #{server} · #{result.channel_count} channels" unless result.reused

    credentials = params[:replace_credentials] == '1' ? 'credentials replaced' : 'stored credentials unchanged'
    "Added #{names} to existing #{server} connection (#{credentials})"
  end

  def server_label(integration)
    integration.hourglass_server_name.presence || integration.hourglass_server_id
  end

  def set_workspace
    @workspace = Workspace.find(params[:workspace_id])
  end

  # A workspace may hold several integrations, so every per-integration action names one explicitly.
  def set_integration
    @integration = @workspace.hourglass_integrations.active.find_by(id: params[:integration_id])
    redirect_with_alert('No active Hourglass connection') unless @integration
  end

  def authorize_workspace_access!
    return if user_has_workspace_access?

    redirect_to root_path, alert: 'Access denied'
  end

  # The workspace owner manages every team; anyone else only the teams they belong to.
  def manageable_teams
    teams = @workspace.teams.not_archived
    current_user == @workspace.owner ? teams : teams.where(id: current_user.teams.select(:id))
  end

  # This controller is workspace-scoped: the route carries workspace_id, so TeamScoped's
  # current_team is whatever the session last held — possibly a team in a different workspace, and
  # nil for a workspace owner who belongs to no team. A connect can also span several teams, so
  # there is no single honest tenant to bill these events to. Emit nothing rather than attribute one
  # team's connect to another team's VEKTIS account.
  def tracked_team
    nil
  end

  def user_has_workspace_access?
    current_user == @workspace.owner ||
      @workspace.teams.joins(:users).where(users: { id: current_user.id }).exists?
  end

  def redirect_with_alert(message)
    redirect_to workspace_settings_hourglass_integration_path(@workspace), alert: message
  end

  def run_connect_service(teams)
    HourglassIntegrations::ConnectService.new(
      workspace: @workspace,
      current_user: current_user,
      base_url: params.require(:base_url),
      api_token: params.require(:api_token),
      teams: teams,
      replace_credentials: params[:replace_credentials] == '1'
    ).call
  end

  def run_test_webhook(integration)
    HourglassIntegrations::TestWebhookService.new(
      integration: integration,
      event_type: params[:event_type].to_s.presence || 'message.created',
      body: params[:body].to_s,
      host: request.host_with_port,
      protocol: request.protocol
    ).call
  end
end
