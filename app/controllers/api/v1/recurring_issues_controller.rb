module Api
  module V1
    class RecurringIssuesController < BaseController
      before_action :set_current_team

      def index
        scope = current_team.recurring_issues.includes(:assignee, :project, :lane, :creator).order(:id)
        since = parse_time(params[:updated_since])
        scope = scope.where('recurring_issues.updated_at > ?', since) if since

        recurring = scope.to_a
        @tracked_result_count = recurring.size
        response.headers['X-Server-Time'] = Time.current.utc.iso8601(6)
        render json: recurring.map { |r| RecurringIssueSerializer.new(r).as_json }
      end

      private

      def parse_time(value)
        Time.iso8601(value) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
