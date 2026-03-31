module Api
  module V1
    class IssuesController < BaseController
      before_action :set_current_team
      before_action :set_issue, only: %i[show update]

      FILTER_PARAMS = %i[lane_id assignee_id project_id priority].freeze

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
        if @issue.update(issue_params)
          render json: serialize(@issue)
        else
          render_validation_errors(@issue)
        end
      end

      private

      def set_issue
        @issue = current_team.issues.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found
      end

      def issue_params
        params.require(:issue).permit(
          :title, :description, :lane_id, :priority, :estimate,
          :due_date, :assignee_id, :project_id, :milestone_id,
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
