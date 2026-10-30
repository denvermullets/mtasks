module Api
  module V1
    class ProjectsController < BaseController
      before_action :set_current_team
      before_action :set_project, only: %i[show update destroy]

      def index
        response.set_header('X-Server-Time', Time.current.utc.iso8601(6))

        scope = current_team.projects.includes(:lead)
        scope = params.key?(:updated_since) ? updated_since_scope(scope) : scope.order(:name)
        return if performed?

        projects = scope.to_a

        @tracked_result_count = projects.size
        render json: projects.map { |p| serialize(p) }
      end

      def show
        render json: serialize(@project, detailed: true)
      end

      def create
        foreign = foreign_team_references(project_params)
        return render_foreign_team_references(foreign) if foreign.any?

        project = current_team.projects.new(project_params)

        if project.save
          track_api_feature('project-management', 'create')
          render json: serialize(project), status: :created
        else
          render_validation_errors(project)
        end
      end

      def update
        foreign = foreign_team_references(project_params)
        return render_foreign_team_references(foreign) if foreign.any?

        if @project.update(project_params)
          track_api_feature('project-management', 'update')
          render json: serialize(@project)
        else
          render_validation_errors(@project)
        end
      end

      def destroy
        @project.destroy
        track_api_feature('project-management', 'delete')
        head :no_content
      end

      private

      def updated_since_scope(scope)
        since = parse_updated_since
        return render_invalid_updated_since unless since

        scope.where(projects: { updated_at: since.. }).order(updated_at: :asc, id: :asc)
      end

      def parse_updated_since
        Time.iso8601(params[:updated_since].to_s)
      rescue ArgumentError
        nil
      end

      def render_invalid_updated_since
        render json: { error: 'Unprocessable Entity', errors: ['updated_since must be an ISO8601 timestamp'] },
               status: :unprocessable_entity
      end

      def set_project
        @project = current_team.projects.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Project not found' }, status: :not_found
      end

      def project_params
        permitted = params.require(:project).permit(
          :name, :description, :priority, :status,
          :lead_id, :start_date, :due_date, :roadmap_commitment, label_ids: []
        )
        permitted[:roadmap_commitment] = nil if permitted[:status] == 'completed'
        permitted
      end

      def serialize(project, detailed: false)
        ProjectSerializer.new(project, detailed: detailed).as_json
      end
    end
  end
end
