module Api
  module V1
    class ActivityController < BaseController
      before_action :set_current_team
      before_action :set_issue

      def index
        entries = VersionDescriptionService.version_entries(@issue)
        render json: entries.map { |v| ActivityEntrySerializer.new(v).as_json }
      end

      private

      def set_issue
        @issue = current_team.issues.find(params[:issue_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found
      end
    end
  end
end
