module Api
  module V1
    class IntegrationsController < BaseController
      def handshake
        return forbid_unless_bootstrap unless bootstrap_token?

        integration = nil
        callback = nil
        ActiveRecord::Base.transaction do
          integration = upsert_integration!
          callback = mint_callback_token(integration)
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

      def mint_callback_token(integration)
        callback = ApiTokens::Issuer.workspace_token(
          user: current_user,
          workspace: integration.workspace,
          name: "Hourglass callback (workspace #{integration.workspace_id})"
        )
        integration.update!(callback_api_token: callback)
        callback
      end
    end
  end
end
