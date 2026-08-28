class Settings::HourglassIntegrationsController < ApplicationController
  before_action :set_workspace
  before_action :authorize_workspace_access!

  def show
    @integrations = @workspace.hourglass_integrations.active.order(:created_at)
  end

  def update
    result = run_connect_service
    track_integration('hourglass-integration', 'link', provider: 'hourglass')
    stash_callback_token(result.integration)
    redirect_to workspace_settings_hourglass_integration_path(@workspace),
                notice: "Connected to #{result.integration.hourglass_server_name} · #{result.channel_count} channels"
  rescue Hourglass::ApiClient::Unauthorized
    redirect_with_alert('Invalid hourglass token')
  rescue Hourglass::ApiClient::Error => e
    Rails.logger.error("Hourglass connect failed: #{e.message}")
    redirect_with_alert("Failed to connect to Hourglass: #{e.message}")
  end

  def test_webhook
    integration = find_integration
    return redirect_with_alert('No active Hourglass connection') unless integration

    result = run_test_webhook(integration)
    if result.success?
      redirect_to workspace_settings_hourglass_integration_path(@workspace),
                  notice: "Test webhook delivered (#{result.delivery_id})"
    else
      redirect_with_alert("Test webhook failed: #{result.error}")
    end
  end

  def destroy
    integration = find_integration
    if integration
      HourglassIntegrations::DisconnectService.new(integration).call
      track_integration('hourglass-integration', 'unlink', provider: 'hourglass')
      flash[:notice] = 'Hourglass disconnected'
    else
      flash[:alert] = 'No active Hourglass connection'
    end

    redirect_to workspace_settings_hourglass_integration_path(@workspace)
  end

  private

  def stash_callback_token(integration)
    flash[:callback_token] = integration.callback_api_token&.raw_token
    flash[:callback_token_integration_id] = integration.id
  end

  def set_workspace
    @workspace = Workspace.find(params[:workspace_id])
  end

  # test_webhook/destroy act on one integration; a workspace may now have several.
  # Fall back to the first active one when no id is supplied.
  def find_integration
    scope = @workspace.hourglass_integrations.active
    params[:integration_id].present? ? scope.find_by(id: params[:integration_id]) : scope.first
  end

  def authorize_workspace_access!
    return if user_has_workspace_access?

    redirect_to root_path, alert: 'Access denied'
  end

  # This controller is workspace-scoped: the route carries workspace_id, so TeamScoped's
  # current_team is whatever the session last held — possibly a team in a different workspace, and
  # nil for a workspace owner who belongs to no team. HourglassIntegration has no team_id either,
  # so there is no honest tenant to bill these events to. Emit nothing rather than attribute one
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

  def run_connect_service
    HourglassIntegrations::ConnectService.new(
      workspace: @workspace,
      current_user: current_user,
      base_url: params.require(:base_url),
      api_token: params.require(:api_token)
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
