module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_token!
      before_action :configure_paper_trail_whodunnit

      private

      def authenticate_api_token!
        token_string = request.headers['Authorization']&.delete_prefix('Bearer ')&.strip
        api_token = ApiToken.authenticate(token_string)

        if api_token
          Current.user = api_token.user
          api_token.touch(:last_used_at)
        else
          render json: { error: 'Unauthorized', message: 'Invalid or missing API token' }, status: :unauthorized
        end
      end

      def current_user
        Current.user
      end

      attr_reader :current_team

      def set_current_team
        @current_team = current_user.teams.not_archived.find_by(id: params[:team_id])
        return if @current_team

        render json: { error: 'Not Found', message: 'Team not found or access denied' }, status: :not_found
      end

      def configure_paper_trail_whodunnit
        ::PaperTrail.request.whodunnit = Current.user&.id&.to_s
      end

      def render_validation_errors(record)
        render json: { error: 'Unprocessable Entity', errors: record.errors.full_messages },
               status: :unprocessable_entity
      end
    end
  end
end
