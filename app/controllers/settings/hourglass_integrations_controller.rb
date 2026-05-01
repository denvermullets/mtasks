class Settings::HourglassIntegrationsController < ApplicationController
  before_action :set_workspace
  before_action :authorize_workspace_access!

  def show
    @integration = @workspace.hourglass_integrations.active.first
  end

  def update
    result = HourglassIntegrations::ConnectService.new(
      workspace: @workspace,
      current_user: current_user,
      base_url: params.require(:base_url),
      api_token: params.require(:api_token)
    ).call

    redirect_to workspace_settings_hourglass_integration_path(@workspace),
                notice: "Connected to #{result.integration.hourglass_server_name} · #{result.channel_count} channels"
  rescue Hourglass::ApiClient::Unauthorized
    redirect_to workspace_settings_hourglass_integration_path(@workspace),
                alert: 'Invalid hourglass token'
  rescue Hourglass::ApiClient::Error => e
    Rails.logger.error("Hourglass connect failed: #{e.message}")
    redirect_to workspace_settings_hourglass_integration_path(@workspace),
                alert: "Failed to connect to Hourglass: #{e.message}"
  end

  def destroy
    integration = @workspace.hourglass_integrations.active.first
    if integration
      HourglassIntegrations::DisconnectService.new(integration).call
      flash[:notice] = 'Hourglass disconnected'
    else
      flash[:alert] = 'No active Hourglass connection'
    end

    redirect_to workspace_settings_hourglass_integration_path(@workspace)
  end

  private

  def set_workspace
    @workspace = Workspace.find(params[:workspace_id])
  end

  def authorize_workspace_access!
    return if user_has_workspace_access?

    redirect_to root_path, alert: 'Access denied'
  end

  def user_has_workspace_access?
    current_user == @workspace.owner ||
      @workspace.teams.joins(:users).where(users: { id: current_user.id }).exists?
  end
end
