class WorkspaceGithubInstallationsController < ApplicationController
  before_action :set_workspace, except: [:callback]
  before_action :authorize_workspace_access!, except: [:callback]

  def show
    @installation = @workspace.github_installation
  end

  def new
    # Redirect to GitHub App installation with workspace_id in state
    state = Base64.urlsafe_encode64({
      workspace_id: @workspace.id,
      timestamp: Time.current.to_i
    }.to_json)

    app_slug = ENV['GITHUB_APP_SLUG']
    redirect_to "https://github.com/apps/#{app_slug}/installations/new?state=#{state}",
                allow_other_host: true
  end

  def callback
    installation_id = params[:installation_id]
    state_data = decode_state(params[:state])

    unless state_data && state_data['workspace_id']
      redirect_to root_path, alert: 'Invalid callback state'
      return
    end

    # Get workspace from state parameter
    @workspace = Workspace.find(state_data['workspace_id'])

    # Authorize access
    unless current_user == @workspace.owner || @workspace.teams.joins(:users).where(users: { id: current_user.id }).exists?
      redirect_to root_path, alert: 'Access denied'
      return
    end

    # Create pending setup (workspace-scoped)
    PendingGithubSetup.create_for_workspace!(
      workspace: @workspace,
      installation_id: installation_id
    )

    # Create installation record
    GhInstallation::CreateForWorkspace.call(
      workspace: @workspace,
      installation_id: installation_id
    )

    redirect_to workspace_github_installation_path(@workspace),
                notice: 'GitHub installation connected! Repositories will sync via webhook.'
  rescue => e
    Rails.logger.error("GitHub installation failed: #{e.message}")
    redirect_to workspace_path(@workspace),
                alert: "Failed to connect GitHub: #{e.message}"
  end

  def destroy
    installation = @workspace.github_installation
    installation&.destroy

    redirect_to workspace_github_installation_path(@workspace),
                notice: 'GitHub installation disconnected'
  end

  private

  def set_workspace
    @workspace = Workspace.find(params[:workspace_id] || params[:id])
  end

  def authorize_workspace_access!
    # Simple authorization - user must be workspace owner or have teams in workspace
    unless current_user == @workspace.owner || @workspace.teams.joins(:users).where(users: { id: current_user.id }).exists?
      redirect_to root_path, alert: 'Access denied'
    end
  end

  def decode_state(state)
    return nil unless state.present?

    JSON.parse(Base64.urlsafe_decode64(state))
  rescue StandardError => e
    Rails.logger.error("Failed to decode state: #{e.message}")
    nil
  end
end
