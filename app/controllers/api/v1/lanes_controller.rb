module Api
  module V1
    class LanesController < BaseController
      before_action :set_current_team

      def index
        lanes = current_team.lanes.order(:position).to_a

        @tracked_result_count = lanes.size
        payload = lanes.map do |l|
          { id: l.id, name: l.name, position: l.position, color: l.color, category: l.category }
        end
        render_conditional_json(payload)
      end
    end
  end
end
