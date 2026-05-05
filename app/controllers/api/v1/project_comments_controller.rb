module Api
  module V1
    class ProjectCommentsController < BaseController
      wrap_parameters :comment, include: %i[body parent_id]

      before_action :set_current_team
      before_action :set_project

      def index
        comments = @project.comments.top_level.includes(:user, replies: :user).order(:created_at)
        render json: comments.map { |c| CommentSerializer.new(c).as_json }
      end

      def create
        if (existing = find_by_hourglass_message_id)
          render json: CommentSerializer.new(existing).as_json, status: :ok
          return
        end

        @comment = @project.comments.new(comment_params)
        @comment.user = Current.user
        @comment.hourglass_message_id = hourglass_message_id

        if @comment.save
          broadcast_to_project_discussion(@comment)
          render json: CommentSerializer.new(@comment).as_json, status: :created
        else
          render_validation_errors(@comment)
        end
      end

      private

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
        params.require(:comment).permit(:body, :parent_id)
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
