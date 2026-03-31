module Api
  module V1
    class LabelsController < BaseController
      before_action :set_current_team

      def index
        labels = current_team.labels.order(:name)
        render json: labels.map { |l|
          { id: l.id, name: l.name, color: l.color }
        }
      end
    end
  end
end
