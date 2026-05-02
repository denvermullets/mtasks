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
    end
  end
end
