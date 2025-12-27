module GhInstallation
  class ProcessCallback < Service
    class InvalidStateError < StandardError; end
    class UnauthorizedError < StandardError; end

    def initialize(current_user:, installation_id:, state_data:)
      @current_user = current_user
      @installation_id = installation_id
      @state_data = state_data
    end

    def call
      validate_state!
      workspace = find_workspace
      authorize_user!(workspace)
      setup_installation(workspace)
      workspace
    end

    private

    def validate_state!
      return if @state_data&.dig('workspace_id')

      raise InvalidStateError, 'Invalid callback state'
    end

    def find_workspace
      Workspace.find(@state_data['workspace_id'])
    end

    def authorize_user!(workspace)
      return if user_authorized?(workspace)

      raise UnauthorizedError, 'Access denied'
    end

    def user_authorized?(workspace)
      @current_user == workspace.owner ||
        workspace.teams.joins(:users).where(users: { id: @current_user.id }).exists?
    end

    def setup_installation(workspace)
      PendingGithubSetup.create_for_workspace!(
        workspace: workspace,
        installation_id: @installation_id
      )

      GhInstallation::CreateForWorkspace.call(
        workspace: workspace,
        installation_id: @installation_id
      )
    end
  end
end
