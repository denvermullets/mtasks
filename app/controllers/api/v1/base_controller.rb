module Api
  module V1
    class BaseController < ActionController::API
      SAFE_METHODS = %w[GET HEAD].freeze

      before_action :authenticate_api_token!
      before_action :authorize_api_token_scope!
      before_action :configure_paper_trail_whodunnit

      private

      def authenticate_api_token!
        token_string = request.headers['Authorization']&.delete_prefix('Bearer ')&.strip
        api_token = ApiToken.authenticate(token_string)

        if api_token
          @current_api_token = api_token
          Current.user = api_token.user
          api_token.touch(:last_used_at)
        else
          render json: { error: 'Unauthorized', message: 'Invalid or missing API token' }, status: :unauthorized
        end
      end

      def authorize_api_token_scope!
        return unless @current_api_token

        required = SAFE_METHODS.include?(request.method) ? 'read' : 'write'
        return if @current_api_token.scopes.include?(required)

        render json: { error: 'Forbidden', message: 'Token lacks required scope' }, status: :forbidden
      end

      def current_user
        Current.user
      end

      attr_reader :current_team

      def set_current_team
        team = current_user.teams.not_archived.find_by(id: params[:team_id])

        if team && token_allows_team?(team)
          @current_team = team
          return
        end

        render json: { error: 'Not Found', message: 'Team not found or access denied' }, status: :not_found
      end

      def token_allows_team?(team)
        return true unless @current_api_token&.scoped_to_team?

        @current_api_token.team_id == team.id
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
