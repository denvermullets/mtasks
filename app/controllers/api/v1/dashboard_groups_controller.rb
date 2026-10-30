module Api
  module V1
    # Groups live on a user-owned dashboard, so every lookup goes through current_user.dashboards and
    # a foreign dashboard or group id is simply not found. Submitted sources are narrowed to
    # accessible_teams (so a team-scoped token can't reach past its teams) by the same sanitizer the
    # web uses; the rest are dropped silently. The web tracks no dashboard feature slug, so there is
    # nothing to reuse and no tenant to file one under.
    class DashboardGroupsController < BaseController
      SOURCE_ID_KEYS = DashboardGroups::SourceSanitizer::KEYS

      before_action :set_dashboard
      before_action :set_group, only: %i[update destroy move]

      def create
        group = DashboardGroup.new(group_attributes.merge(dashboard_id: @dashboard.id))
        group.position = @dashboard.groups.maximum(:position).to_i + 1
        save_and_render(group, :created)
      end

      def update
        @group.assign_attributes(group_attributes)
        save_and_render(@group, :ok)
      end

      def destroy
        @group.destroy
        head :no_content
      end

      def move
        direction = params[:direction]
        unless DashboardGroup::DIRECTIONS.include?(direction)
          return render json: { error: 'Bad Request', message: 'direction must be up or down' }, status: :bad_request
        end

        @group.move!(direction)
        render json: serialize_all
      end

      # Every group id on the dashboard is accepted in display order; ids that don't belong to it are
      # rejected rather than ignored, and groups left out keep their relative order at the end.
      def reorder
        ids = Array(params[:ids]).map(&:to_i)
        unless (ids - @dashboard.groups.pluck(:id)).empty?
          return render json: { error: 'Unprocessable Entity', message: 'ids must belong to the dashboard' },
                        status: :unprocessable_entity
        end

        @dashboard.reorder_groups!(ids)
        render json: serialize_all
      end

      private

      def set_dashboard
        @dashboard = current_user.dashboards.find_by(id: params[:dashboard_id])
        return if @dashboard

        render json: { error: 'Not Found', message: 'Dashboard not found' }, status: :not_found
      end

      def set_group
        @group = @dashboard.groups.find_by(id: params[:id])
        return if @group

        render json: { error: 'Not Found', message: 'Group not found' }, status: :not_found
      end

      def save_and_render(group, status)
        sources = DashboardGroups::SourceSanitizer.call(teams: accessible_teams, params: group_params)
        saved = DashboardGroup.transaction { group.save && group.replace_sources!(**sources) }
        return render_validation_errors(group) unless saved

        render json: serialize(group), status: status
      end

      def group_params
        params.require(:dashboard_group).permit(:name, :description, :color, **SOURCE_ID_KEYS.index_with([]))
      end

      def group_attributes
        group_params.except(*SOURCE_ID_KEYS)
      end

      # The dashboard serializer's group shape, so a write returns exactly what the list would.
      def serialize(group)
        serialize_all.find { |g| g[:id] == group.id }
      end

      def serialize_all
        dashboard = Dashboard.includes(groups: :sources).find(@dashboard.id)
        DashboardSerializer.new(dashboard, allowed: allowed_source_ids).as_json[:groups]
      end

      def allowed_source_ids
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
