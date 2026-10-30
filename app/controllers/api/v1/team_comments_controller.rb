module Api
  module V1
    # Flat feed of every issue and project comment in a team, for syncing in one call.
    class TeamCommentsController < BaseController
      before_action :set_current_team

      def index
        response.set_header('X-Server-Time', Time.current.utc.iso8601(6))

        scope = team_comments
        if params.key?(:updated_since)
          since = parse_updated_since
          return render_invalid_updated_since unless since

          scope = scope.where(comments: { updated_at: since.. })
        end

        comments = scope.order(updated_at: :asc, id: :asc).to_a
        @tracked_result_count = comments.size
        render json: comments.map { |c| serialize(c) }
      end

      private

      def team_comments
        Comment.where(issue_id: current_team.issues.select(:id))
               .or(Comment.where(project_id: current_team.projects.select(:id)))
               .includes(:user)
      end

      def serialize(comment)
        CommentSerializer.new(comment, include_replies: false).as_json.merge(
          issue_id: comment.issue_id,
          project_id: comment.project_id,
          owner_type: comment.issue_id ? 'Issue' : 'Project',
          owner_id: comment.issue_id || comment.project_id
        )
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
    end
  end
end
