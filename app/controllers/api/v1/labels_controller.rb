module Api
  module V1
    class LabelsController < BaseController
      before_action :set_current_team

      def index
        labels = current_team.labels.order(:name).to_a

        @tracked_result_count = labels.size
        render json: labels.map { |l| serialize(l) }
      end

      def create
        label = current_team.labels.new(label_params)
        label.color ||= Label.random_color

        if label.save
          track_api_feature('label-management', 'create')
          render json: serialize(label), status: :created
        else
          render_validation_errors(label)
        end
      end

      private

      def label_params
        params.require(:label).permit(:name, :color)
      end

      def serialize(label)
        { id: label.id, name: label.name, color: label.color }
      end
    end
  end
end
