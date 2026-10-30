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

      def create
        foreign = foreign_team_references(recurring_issue_params)
        return render_foreign_team_references(foreign) if foreign.any?

        recurring = current_team.recurring_issues.new(time_zone: current_user.time_zone)
        recurring.assign_attributes(recurring_issue_params)
        recurring.creator = current_user
        recurring.schedule_from(start_date)

        if recurring.save
          render json: RecurringIssueSerializer.new(recurring).as_json, status: :created
        else
          render_validation_errors(recurring)
        end
      end

      private

      def recurring_issue_params
        params.require(:recurring_issue)
              .permit(:title, :description, :priority, :assignee_id, :project_id, :lane_id,
                      :frequency, :interval, :weekday, :day_of_month, :time_zone, :active, label_ids: [])
      end

      # An unparseable or missing date leaves next_run_on blank so validation reports it.
      def start_date
        Date.iso8601(params.dig(:recurring_issue, :starts_on).to_s)
      rescue Date::Error
        nil
      end

      def parse_time(value)
        Time.iso8601(value) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
