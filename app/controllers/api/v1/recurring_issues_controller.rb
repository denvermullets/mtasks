module Api
  module V1
    class RecurringIssuesController < BaseController
      before_action :set_current_team
      before_action :set_recurring_issue, only: %i[update destroy]

      def index
        since = parse_time_param(:updated_since)
        return if performed?

        scope = current_team.recurring_issues.includes(:assignee, :project, :lane, :creator).order(:id)
        scope = scope.where('recurring_issues.updated_at > ?', since) if since

        recurring = scope.to_a
        @tracked_result_count = recurring.size
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

      def update
        foreign = foreign_team_references(recurring_issue_params)
        return render_foreign_team_references(foreign) if foreign.any?

        @recurring_issue.assign_attributes(recurring_issue_params)
        # Only a supplied starts_on reschedules, so pausing/resuming keeps the stored next run.
        @recurring_issue.schedule_from(start_date) if params.dig(:recurring_issue, :starts_on).present?

        if @recurring_issue.save
          render json: RecurringIssueSerializer.new(@recurring_issue).as_json
        else
          render_validation_errors(@recurring_issue)
        end
      end

      def destroy
        @recurring_issue.destroy
        head :no_content
      end

      private

      def set_recurring_issue
        @recurring_issue = current_team.recurring_issues.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Recurring issue not found' }, status: :not_found
      end

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
    end
  end
end
