module Api
  module V1
    class ProjectsController < BaseController
      before_action :set_current_team

      def index
        projects = current_team.projects.order(:name)
        render json: projects.map { |p|
          { id: p.id, name: p.name, description: p.description }
        }
      end
    end
  end
end
