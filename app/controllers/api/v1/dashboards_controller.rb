module Api
  module V1
    # Dashboards are user-owned, not team-scoped, so every lookup goes through current_user.dashboards
    # and another user's id is simply not found. Group sources are filtered to accessible_teams on read.
    # The web tracks no dashboard feature slug, so there is nothing to reuse and no tenant to file one under.
    class DashboardsController < BaseController
      before_action :set_dashboard, only: %i[show update destroy]

      def index
        dashboards = current_user.dashboards.includes(groups: :sources).to_a

        @tracked_result_count = dashboards.size
        render json: dashboards.map { |d| serialize(d) }
      end

      def show
        render json: serialize(@dashboard)
      end

      def create
        dashboard = Dashboard.new(dashboard_params.merge(user: current_user))
        dashboard.position = current_user.dashboards.maximum(:position).to_i + 1

        if dashboard.save
          render json: serialize(dashboard), status: :created
        else
          render_validation_errors(dashboard)
        end
      end

      def update
        if @dashboard.update(dashboard_params)
          render json: serialize(@dashboard)
        else
          render_validation_errors(@dashboard)
        end
      end

      def destroy
        @dashboard.destroy
        head :no_content
      end

      private

      def set_dashboard
        @dashboard = current_user.dashboards.includes(groups: :sources).find_by(id: params[:id])
        return if @dashboard

        render json: { error: 'Not Found', message: 'Dashboard not found' }, status: :not_found
      end

      def dashboard_params
        params.require(:dashboard).permit(:name, :description)
      end

      def serialize(dashboard)
        DashboardSerializer.new(dashboard, allowed: allowed_source_ids).as_json
      end

      def allowed_source_ids
        @allowed_source_ids ||= begin
          team_ids = accessible_teams.pluck(:id)
          {
            'Team' => team_ids,
            'Project' => Project.where(team_id: team_ids).pluck(:id),
            'Label' => Label.where(team_id: team_ids).pluck(:id)
          }
        end
      end
    end
  end
end
