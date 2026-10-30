module Api
  module V1
    # Flat feed of every issue and project comment in a team, for syncing in one call.
    class TeamCommentsController < BaseController
      before_action :set_current_team

      def index
        since = parse_time_param(:updated_since)
        return if performed?

        scope = team_comments
        scope = scope.where(comments: { updated_at: since.. }) if since

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
    end
  end
end
