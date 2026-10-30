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

        blobs = find_blobs
        return render_invalid_files if blobs.nil?

        @comment = build_comment(blobs)

        if @comment.save
          @issue.touch # a comment is a change to the issue; surfaces it in updated_since pulls
          after_create_side_effects(@comment)
          # Only this branch. The Idempotency-Key short-circuit above returns an existing comment,
          # which is a redelivery rather than new activity and must not be counted twice.
          track_api_feature('comment', 'create', entity: 'issue', depth: @comment.depth)
          render json: CommentSerializer.new(@comment).as_json, status: :created
        else
          render_validation_errors(@comment)
        end
      end

      def destroy
        comment = @issue.comments.find(params[:id])
        return render_forbidden('Only the author or a team admin can delete this') unless can_modify?(comment)

        depth = comment.depth
        comment.destroy! # replies cascade via dependent: :destroy
        @issue.touch # a deletion is a change to the issue; surfaces it in updated_since pulls
        track_api_feature('comment', 'delete', entity: 'issue', depth: depth)
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Comment not found' }, status: :not_found
      end

      def destroy_attachment
        comment = @issue.comments.find(params[:comment_id])
        return render_forbidden('Only the author or a team admin can remove this') unless can_modify?(comment)

        comment.files_attachments.find(params[:id]).purge
        @issue.touch
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Comment attachment not found' }, status: :not_found
      end

      private

      def can_modify?(comment)
        comment.user_id == Current.user.id || current_team.admin?(Current.user)
      end

      def render_forbidden(message)
        render json: { error: 'Forbidden', message: message }, status: :forbidden
      end

      def build_comment(blobs)
        comment = @issue.comments.new(comment_params)
        comment.user = Current.user
        comment.hourglass_message_id = hourglass_message_id
        comment.files.attach(blobs) if blobs.any?
        comment
      end

      # [] when no files were sent; nil when any id doesn't resolve, so a bad batch creates nothing.
      def find_blobs
        ids = Array(params[:files]).compact_blank
        blobs = ids.map { |id| ActiveStorage::Blob.find_signed(id) }
        blobs.all? ? blobs.uniq : nil
      end

      def render_invalid_files
        render json: { error: 'Unprocessable Entity', errors: ['files must be valid signed ids'] },
               status: :unprocessable_entity
      end

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
        params.require(:comment).permit(:body, :parent_id) # files handled by find_blobs
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
