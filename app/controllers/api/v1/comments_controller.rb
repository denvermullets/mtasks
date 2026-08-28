module Api
  module V1
    class CommentsController < BaseController
      include MentionNotifying

      before_action :set_current_team
      before_action :set_issue

      def index
        comments = @issue.comments.top_level.includes(:user, replies: :user).order(:created_at).to_a

        @tracked_result_count = comments.size
        render json: comments.map { |c| CommentSerializer.new(c).as_json }
      end

      def create
        if (existing = find_by_hourglass_message_id)
          render json: CommentSerializer.new(existing).as_json, status: :ok
          return
        end

        @comment = @issue.comments.new(comment_params)
        @comment.user = Current.user
        @comment.hourglass_message_id = hourglass_message_id

        if @comment.save
          after_create_side_effects(@comment)
          # Only this branch. The Idempotency-Key short-circuit above returns an existing comment,
          # which is a redelivery rather than new activity and must not be counted twice.
          track_api_feature('comment', 'create', entity: 'issue', depth: @comment.depth)
          render json: CommentSerializer.new(@comment).as_json, status: :created
        else
          render_validation_errors(@comment)
        end
      end

      private

      def after_create_side_effects(comment)
        IssueReferenceService.call(source_issue: @issue, text: comment.body,
                                   source_type: 'comment', user: Current.user)
        NotificationService.call(issue: @issue, actor: Current.user, action: 'commented', comment: comment)
        notify_mentions_on(@issue, text: comment.body, comment: comment)
        broadcast_to_issue_discussion(comment)
      end

      def broadcast_to_issue_discussion(comment)
        Turbo::StreamsChannel.broadcast_append_to(
          "issue_#{@issue.id}_discussion",
          target: "issue_discussion_stream_#{@issue.id}",
          partial: 'projects/discussion_native_comment',
          locals: { comment: comment, team: @issue.team }
        )
      end

      def set_issue
        @issue = current_team.issues.find(params[:issue_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found
      end

      def comment_params
        params.require(:comment).permit(:body, :parent_id)
      end

      def hourglass_message_id
        request.headers['Idempotency-Key'].presence
      end

      def find_by_hourglass_message_id
        return nil unless hourglass_message_id

        @issue.comments.find_by(hourglass_message_id: hourglass_message_id)
      end
    end
  end
end
