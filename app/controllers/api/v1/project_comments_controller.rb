module Api
  module V1
    class ProjectCommentsController < BaseController
      include ApiCommentFiles

      wrap_parameters :comment, include: %i[body parent_id]

      before_action :set_current_team
      before_action :set_project

      def index
        comments = @project.comments.top_level.includes(:user, replies: :user).order(:created_at).to_a

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
          @project.touch # a comment is a change to the project; surfaces it in updated_since pulls
          broadcast_to_project_discussion(@comment)
          # Only this branch — the hourglass_message_id short-circuit above is a redelivery.
          track_api_feature('comment', 'create', entity: 'project', depth: @comment.depth)
          track_comment_files(blobs)
          render json: CommentSerializer.new(@comment).as_json, status: :created
        else
          render_validation_errors(@comment)
        end
      end

      def destroy_attachment
        comment = @project.comments.find(params[:comment_id])
        return render_forbidden('Only the author or a team admin can remove this') unless can_modify?(comment)

        comment.files_attachments.find(params[:id]).purge
        @project.touch
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Comment attachment not found' }, status: :not_found
      end

      private

      def build_comment(blobs)
        comment = @project.comments.new(comment_params)
        comment.user = Current.user
        comment.hourglass_message_id = hourglass_message_id
        comment.files.attach(blobs) if blobs.any?
        comment
      end

      def broadcast_to_project_discussion(comment)
        Turbo::StreamsChannel.broadcast_append_to(
          "project_#{@project.id}_discussion",
          target: 'discussion-stream',
          partial: 'projects/discussion_native_comment',
          locals: { comment: comment, project: @project }
        )
      end

      def set_project
        @project = current_team.projects.find(params[:project_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Project not found' }, status: :not_found
      end

      def comment_params
        params.fetch(:comment, {}).permit(:body, :parent_id) # files handled by find_blobs
      end

      def hourglass_message_id
        request.headers['Idempotency-Key'].presence
      end

      def find_by_hourglass_message_id
        return nil unless hourglass_message_id

        @project.comments.find_by(hourglass_message_id: hourglass_message_id)
      end
    end
  end
end
