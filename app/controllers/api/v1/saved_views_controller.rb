module Api
  module V1
    # Personal saved views. They belong to the user, so every lookup goes through
    # current_user.saved_views, narrowed to the teams the token can see.
    class SavedViewsController < BaseController
      before_action :set_current_team, only: :create

      def index
        views = visible_views
        if params[:updated_since].present?
          since = parse_time(params[:updated_since])
          return render_invalid_since unless since

          views = views.where('saved_views.updated_at > ?', since)
        end

        @tracked_result_count = views.size
        render json: views.map { |v| SavedViewSerializer.new(v).as_json }
      end

      def create
        view = SavedView.new(
          user: current_user, team: current_team, name: saved_view_params[:name],
          query: SavedView.query_from(query_string(saved_view_params[:query])),
          position: current_user.saved_views.maximum(:position).to_i + 1
        )

        if view.save
          render json: SavedViewSerializer.new(view).as_json, status: :created
        else
          render_validation_errors(view)
        end
      end

      private

      def visible_views
        views = current_user.saved_views.where(team_id: accessible_teams.select(:id))
        params[:team_id].present? ? views.where(team_id: params[:team_id]) : views
      end

      def saved_view_params
        params.require(:saved_view).permit(:name, :query, query: {})
      end

      # The query arrives as a JSON object or a query string; both end up as a query string
      # for SavedView.query_from, which keeps only QUERY_KEYS.
      def query_string(query)
        query.respond_to?(:to_h) ? query.to_h.to_query : query.to_s
      end

      def parse_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def render_invalid_since
        render json: { error: 'Unprocessable Entity', errors: ['updated_since must be ISO8601'] },
               status: :unprocessable_entity
      end
    end
  end
end
