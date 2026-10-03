module Api
  module V1
    class IntegrationsController < BaseController
      def handshake
        return forbid_unless_bootstrap unless bootstrap_token?

        teams = bootstrap_teams
        return reject_without_teams if teams.empty?

        integration = nil
        callback = nil
        ActiveRecord::Base.transaction do
          integration = upsert_integration!
          callback = mint_callback_token(integration)
          HourglassIntegrations::SubscribeTeamsService.call(integration: integration, teams: teams)
          @current_api_token.revoke!
        end

        render json: {
          integration_id: integration.id,
          workspace_id: integration.workspace_id,
          callback_token: callback.raw_token
        }, status: :created
      end

      private

      def bootstrap_token?
        @current_api_token.one_time_use? &&
          @current_api_token.workspace_id.present? &&
          !@current_api_token.revoked?
      end

      def forbid_unless_bootstrap
        render json: { error: 'Forbidden', message: 'Bootstrap token required' }, status: :forbidden
      end

      # The bootstrap token's own team set names which teams the connection is for; an unscoped one
      # would mean every team in the workspace, which is exactly the fan-out connections no longer do.
      def bootstrap_teams
        return [] unless @current_api_token.team_scoped?

        @current_api_token.workspace.teams.where(id: @current_api_token.scoped_team_ids).to_a
      end

      def reject_without_teams
        render json: { error: 'Unprocessable', message: 'Bootstrap token must be scoped to teams in its workspace' },
               status: :unprocessable_entity
      end

      def upsert_integration!
        workspace = @current_api_token.workspace
        integration = workspace.hourglass_integrations.find_or_initialize_by(
          hourglass_server_id: params.require(:hourglass_server_id)
        )
        integration.assign_attributes(
          hourglass_server_name: params[:hourglass_server_name],
          base_url: params.require(:base_url),
          api_token: params.require(:api_token),
          webhook_secret: params[:webhook_secret] || SecureRandom.hex(32),
          connected_by_user: current_user,
          connected_at: Time.current,
          last_verified_at: Time.current,
          active: true
        )
        integration.save!
        integration
      end

      # Starts with no teams: SubscribeTeamsService then scopes it to the integration's active
      # subscriptions. A re-handshake rotates the token, so the old one is revoked.
      def mint_callback_token(integration)
        previous = integration.live_callback_token
        callback = ApiTokens::Issuer.call(
          user: current_user,
          teams: [],
          name: "Hourglass callback (#{integration.hourglass_server_name || integration.hourglass_server_id})"
        )
        integration.update!(callback_api_token: callback)
        previous&.revoke!
        callback
      end
    end
  end
end
