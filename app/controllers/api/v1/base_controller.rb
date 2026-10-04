module Api
  module V1
    class BaseController < ActionController::API
      # Every API and MCP call passes through here, which is what makes this the one place that
      # can see agent traffic at all. See the concern for why the API is a catalogued surface now.
      include VektisApiTracking

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

      # Every team-resolving lookup goes through this, so a team-scoped token never sees a team
      # outside its set — not even to learn that it exists.
      def accessible_teams
        @current_api_token.filter_teams(current_user.teams.not_archived)
      end

      def set_current_team
        @current_team = accessible_teams.find_by(id: params[:team_id])
        return if @current_team

        render json: { error: 'Not Found', message: 'Team not found or access denied' }, status: :not_found
      end

      # Ids a client sends for related records are only checked by the database for existence, not
      # tenancy, so without this a token scoped to one team could hang its writes off another
      # team's projects, labels or issues. Run it before assign_attributes: label_ids writes its
      # join rows the moment it is assigned on a persisted record.
      def foreign_team_references(attrs)
        team_reference_scopes.filter_map do |key, scope|
          ids = Array(attrs[key]).compact_blank.map(&:to_s).uniq
          key if ids.any? && scope.where(id: ids).count != ids.size
        end
      end

      def team_reference_scopes
        {
          'lane_id' => current_team.lanes, 'project_id' => current_team.projects,
          'parent_issue_id' => current_team.issues, 'label_ids' => current_team.labels,
          'assignee_id' => current_team.users, 'lead_id' => current_team.users
        }
      end

      def render_foreign_team_references(keys)
        render json: { error: 'Unprocessable Entity', errors: keys.map { |k| "#{k} does not belong to this team" } },
               status: :unprocessable_entity
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
