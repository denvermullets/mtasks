module Api
  module V1
    class UsersController < BaseController
      def me
        render json: {
          id: current_user.id,
          name: current_user.name,
          email: current_user.email,
          token: {
            name: @current_api_token.name,
            scopes: @current_api_token.scopes,
            team_ids: token_team_ids,
            # Pre-team-set clients read a single team_id; keep it for one-team tokens.
            team_id: token_team_ids&.one? ? token_team_ids.first : nil
          }
        }
      end

      def by_email
        email = params[:email].to_s.strip.downcase
        return render json: { error: 'Bad Request', message: 'email is required' }, status: :bad_request if email.blank?

        user = User.where('LOWER(email) = ?', email)
                   .joins(:teams)
                   .where(teams: { id: accessible_teams.select(:id) })
                   .distinct
                   .first
        return render json: { error: 'Not Found' }, status: :not_found unless user

        render json: { id: user.id, name: user.name, email: user.email }
      end

      private

      def token_team_ids
        return @token_team_ids if defined?(@token_team_ids)

        @token_team_ids = @current_api_token.team_scoped? ? @current_api_token.scoped_team_ids.sort : nil
      end
    end
  end
end
