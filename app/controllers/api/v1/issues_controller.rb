module Api
  module V1
    class IssuesController < BaseController
      before_action :set_current_team, except: [:by_identifier]
      before_action :set_issue, only: %i[show update]

      FILTER_PARAMS = %i[lane_id assignee_id project_id priority].freeze

      def by_identifier
        team_identifier, number_str = params[:identifier].split('-', 2)
        team = current_user.teams.not_archived.find_by(identifier: team_identifier)
        return render_not_found unless team && token_allows_team?(team)

        issue = team.issues.find_by(team_number: number_str.to_i)
        return render_not_found unless issue

        render json: IssueSerializer.new(issue, detailed: true).as_json
      end

      def index
        issues = filter_issues(
          current_team.issues.not_archived.includes(:lane, :project, :labels, :assignee, :creator)
        )

        render json: issues.order(created_at: :desc).map { |i| serialize(i) }
      end

      def show
        render json: serialize(@issue, detailed: true)
      end

      def create
        issue = current_team.issues.new(issue_params)
        issue.creator = current_user

        if issue.save
          render json: serialize(issue), status: :created
        else
          render_validation_errors(issue)
        end
      end

      def update
        @issue.assign_attributes(issue_params)
        @issue.apply_lane_timestamps!

        if @issue.save
          @issue.enqueue_velocity_recalculation!
          IssueAfterUpdateJob.perform_later(issue_id: @issue.id, user_id: current_user.id)
          render json: serialize(@issue)
        else
          render_validation_errors(@issue)
        end
      end

      private

      def set_issue
        @issue = current_team.issues.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def render_not_found
        render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found
      end

      def issue_params
        params.require(:issue).permit(
          :title, :description, :lane_id, :priority, :estimate,
          :due_date, :assignee_id, :project_id,
          :parent_issue_id, label_ids: []
        )
      end

      def filter_issues(issues)
        FILTER_PARAMS.each do |key|
          issues = issues.where(key => params[key]) if params[key]
        end
        issues
      end

      def serialize(issue, detailed: false)
        IssueSerializer.new(issue, detailed: detailed).as_json
      end
    end
  end
end
