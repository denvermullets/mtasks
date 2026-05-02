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
            team_id: @current_api_token.team_id
          }
        }
      end

      def by_email
        email = params[:email].to_s.strip.downcase
        return render json: { error: 'Bad Request', message: 'email is required' }, status: :bad_request if email.blank?

        user = User.where('LOWER(email) = ?', email)
                   .joins(:teams)
                   .where(teams: { id: current_user.team_ids })
                   .distinct
                   .first
        return render json: { error: 'Not Found' }, status: :not_found unless user

        render json: { id: user.id, name: user.name, email: user.email }
      end
    end
  end
end
