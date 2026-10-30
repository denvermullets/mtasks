module Api
  module V1
    class LabelsController < BaseController
      before_action :set_current_team
      before_action :set_label, only: :update

      def index
        labels = current_team.labels.order(:name).to_a

        @tracked_result_count = labels.size
        render_conditional_json(labels.map { |l| serialize(l) })
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

      def update
        if @label.update(label_params)
          track_api_feature('label-management', 'update')
          render json: serialize(@label)
        else
          render_validation_errors(@label)
        end
      end

      private

      def set_label
        @label = current_team.labels.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Label not found' }, status: :not_found
      end

      def label_params
        params.require(:label).permit(:name, :color)
      end

      def serialize(label)
        { id: label.id, name: label.name, color: label.color, updated_at: label.updated_at }
      end
    end
  end
end
