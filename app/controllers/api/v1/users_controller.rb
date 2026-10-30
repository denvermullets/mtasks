module Api
  module V1
    class UsersController < BaseController
      def me
        render json: {
          id: current_user.id,
          name: current_user.name,
          email: current_user.email,
          home_page: home_page_json,
          token: {
            name: @current_api_token.name,
            scopes: @current_api_token.scopes,
            team_ids: token_team_ids,
            # Pre-team-set clients read a single team_id; keep it for one-team tokens.
            team_id: token_team_ids&.one? ? token_team_ids.first : nil
          }
        }
      end

      # PUT /me/home_page with {kind, id} or the web's {home: "team:3"}; blank clears it.
      def update_home_page
        kind, id = home_page_params
        unless current_user.set_home_page(kind, id, within_teams: accessible_teams)
          return render json: { error: 'Unprocessable Entity', errors: ['Unknown home page'] },
                        status: :unprocessable_entity
        end

        render json: { home_page: current_user.home_page }
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

      def home_page_params
        return params[:home].to_s.split(':', 2) if params[:home].present?

        [params[:kind].to_s, params[:id].to_s]
      end

      # A token scoped to some teams must not reveal a home page in another team.
      def home_page_json
        page = current_user.home_page
        return page unless page && token_team_ids

        page if page[:kind] == 'dashboard' || token_team_ids.include?(home_page_team_id(page))
      end

      def home_page_team_id(page)
        return page[:id] if page[:kind] == 'team'

        current_user.saved_views.find_by(id: page[:id])&.team_id
      end

      def token_team_ids
        return @token_team_ids if defined?(@token_team_ids)

        @token_team_ids = @current_api_token.team_scoped? ? @current_api_token.scoped_team_ids.sort : nil
      end
    end
  end
end
