module Api
  module V1
    class LanesController < BaseController
      before_action :set_current_team

      def index
        lanes = current_team.lanes.order(:position)
        render json: lanes.map { |l|
          { id: l.id, name: l.name, position: l.position, color: l.color }
        }
      end
    end
  end
end
