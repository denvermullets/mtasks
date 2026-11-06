module Api
  module V1
    class UsersController < BaseController
      def me
        render json: {
          id: current_user.id,
          name: current_user.name,
          email: current_user.email,
          home_page: home_page_json,
          sidebar: sidebar_json,
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

      # PATCH /me/sidebar_groups/:id with {collapsed: bool}. Only the collapsed state is settable here;
      # creating, renaming, deleting and regrouping teams stay web-only.
      def update_sidebar_group
        unless params.key?(:collapsed)
          return render json: { error: 'Unprocessable Entity', errors: ['collapsed is required'] },
                        status: :unprocessable_entity
        end

        group = current_user.update_sidebar_group(params[:id], collapsed: params[:collapsed])
        return render json: { error: 'Not Found', message: 'Sidebar group not found' }, status: :not_found unless group

        render json: visible_sidebar_group(group, accessible_teams.pluck(:id).to_set)
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

      # Raw sidebar settings; the client resolves the layout the way User#sidebar_layout does. Ids of
      # teams the token can't see (out of scope, archived, or left) are dropped, but groups are kept
      # even when that empties them.
      def sidebar_json
        visible = accessible_teams.pluck(:id).to_set
        order = current_user.team_order
        {
          groups: current_user.sidebar_groups.map { |group| visible_sidebar_group(group, visible) },
          team_order: {
            owned: order['owned'].select { |id| visible.include?(id) },
            joined: order['joined'].select { |id| visible.include?(id) }
          }
        }
      end

      def visible_sidebar_group(group, visible_team_ids)
        group.merge('team_ids' => group['team_ids'].select { |id| visible_team_ids.include?(id) })
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
