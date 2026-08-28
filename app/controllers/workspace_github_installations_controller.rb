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

    app_slug = ENV.fetch('GITHUB_APP_SLUG', nil)
    redirect_to "https://github.com/apps/#{app_slug}/installations/new?state=#{state}",
                allow_other_host: true
  end

  def callback
    @workspace = GhInstallation::ProcessCallback.call(
      current_user: current_user,
      installation_id: params[:installation_id],
      state_data: decode_state(params[:state])
    )
    track_integration('github-integration', 'link', provider: 'github')

    redirect_to workspace_github_installation_path(@workspace),
                notice: 'GitHub installation connected! Repositories will sync via webhook.'
  rescue GhInstallation::ProcessCallback::InvalidStateError
    redirect_to root_path, alert: 'Invalid callback state'
  rescue GhInstallation::ProcessCallback::UnauthorizedError
    redirect_to root_path, alert: 'Access denied'
  rescue StandardError => e
    Rails.logger.error("GitHub installation failed: #{e.message}")
    redirect_to root_path, alert: "Failed to connect GitHub: #{e.message}"
  end

  def destroy
    installation = @workspace.github_installation
    track_integration('github-integration', 'unlink', provider: 'github') if installation&.destroy

    redirect_to workspace_github_installation_path(@workspace),
                notice: 'GitHub installation disconnected'
  end

  private

  def set_workspace
    @workspace = Workspace.find(params[:workspace_id] || params[:id])
  end

  def authorize_workspace_access!
    return if user_has_workspace_access?

    redirect_to root_path, alert: 'Access denied'
  end

  def user_has_workspace_access?
    current_user == @workspace.owner ||
      @workspace.teams.joins(:users).where(users: { id: current_user.id }).exists?
  end

  def decode_state(state)
    return nil unless state.present?

    JSON.parse(Base64.urlsafe_decode64(state))
  rescue StandardError => e
    Rails.logger.error("Failed to decode state: #{e.message}")
    nil
  end
end
