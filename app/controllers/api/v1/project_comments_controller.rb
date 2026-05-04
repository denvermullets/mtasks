module Api
  module V1
    class ProjectCommentsController < BaseController
      before_action :set_current_team
      before_action :set_project

      def index
        comments = @project.comments.top_level.includes(:user, replies: :user).order(:created_at)
        render json: comments.map { |c| CommentSerializer.new(c).as_json }
      end

      def create
        @comment = @project.comments.new(comment_params)
        @comment.user = Current.user

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
    end
  end
end
