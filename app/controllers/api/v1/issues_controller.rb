module Api
  module V1
    class IssuesController < BaseController
      before_action :set_current_team, except: [:by_identifier]
      before_action :set_issue, only: %i[show update destroy]

      # Below the before_action block on purpose: capture_tracked_label_ids has to run after
      # set_issue, because it reads label_ids before update rewrites them.
      include VektisApiIssueTracking

      FILTER_PARAMS = %i[lane_id assignee_id project_id priority].freeze

      def by_identifier
        team_identifier, number_str = params[:identifier].split('-', 2)
        team = accessible_teams.find_by(identifier: team_identifier)
        return render_not_found unless team

        # This route resolves its own tenant rather than going through set_current_team; assigning
        # it here is what lets the read event be attributed instead of silently dropped.
        @current_team = team

        issue = team.issues.find_by(team_number: number_str.to_i)
        return render_not_found unless issue

        render json: IssueSerializer.new(issue, detailed: true).as_json
      end

      def index
        response.set_header('X-Server-Time', Time.current.utc.iso8601(6))

        scope = filter_issues(
          current_team.issues.not_archived.includes(:lane, :project, :labels, :assignee, :creator)
        )
        scope = params.key?(:updated_since) ? updated_since_scope(scope) : scope.order(created_at: :desc)
        return if performed?

        issues = scope.to_a
        @tracked_result_count = issues.size
        render json: issues.map { |i| serialize(i) }
      end

      def show
        render json: serialize(@issue, detailed: true)
      end

      def create
        foreign = foreign_team_references(issue_params)
        return render_foreign_team_references(foreign) if foreign.any?

        issue = current_team.issues.new(issue_params)
        issue.creator = current_user

        if issue.save
          HourglassOutboundEmitterJob.dispatch_create(issue, current_user)
          track_api_issue_created(issue)
          render json: serialize(issue), status: :created
        else
          render_validation_errors(issue)
        end
      end

      def update
        foreign = foreign_team_references(issue_params)
        return render_foreign_team_references(foreign) if foreign.any?

        @issue.assign_attributes(issue_params)
        @issue.apply_lane_timestamps!

        if @issue.save
          @issue.enqueue_velocity_recalculation!
          IssueAfterUpdateJob.perform_later(
            issue_id: @issue.id, user_id: current_user.id, version_id: @issue.versions.last&.id
          )
          track_api_issue_updated
          render json: serialize(@issue)
        else
          render_validation_errors(@issue)
        end
      end

      # Mirrors the web destroy: any team member may delete, and the project's velocity is
      # recalculated afterwards. The write is tracked as issue-delete, the web's slug.
      def destroy
        project_id = @issue.project_id
        @issue.destroy
        return render_validation_errors(@issue) unless @issue.destroyed?

        track_api_feature('issue-delete', 'delete', **issue_shape(@issue))
        ProjectVelocityJob.perform_later(project_id) if project_id.present?
        head :no_content
      end

      private

      def set_issue
        @issue = current_team.issues.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def updated_since_scope(scope)
        since = parse_updated_since
        return render_invalid_updated_since unless since

        scope.where(issues: { updated_at: since.. }).order(updated_at: :asc, id: :asc)
      end

      def parse_updated_since
        Time.iso8601(params[:updated_since].to_s)
      rescue ArgumentError
        nil
      end

      def render_invalid_updated_since
        render json: { error: 'Unprocessable Entity', errors: ['updated_since must be an ISO8601 timestamp'] },
               status: :unprocessable_entity
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
