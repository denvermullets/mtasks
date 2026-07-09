module Api
  module V1
    class ProjectsController < BaseController
      before_action :set_current_team
      before_action :set_project, only: %i[show update destroy]

      def index
        projects = current_team.projects.includes(:lead).order(:name)
        render json: projects.map { |p| serialize(p) }
      end

      def show
        render json: serialize(@project, detailed: true)
      end

      def create
        project = current_team.projects.new(project_params)

        if project.save
          render json: serialize(project), status: :created
        else
          render_validation_errors(project)
        end
      end

      def update
        if @project.update(project_params)
          render json: serialize(@project)
        else
          render_validation_errors(@project)
        end
      end

      def destroy
        @project.destroy
        head :no_content
      end

      private

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
