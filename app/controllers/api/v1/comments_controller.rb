module Api
  module V1
    class CommentsController < BaseController
      include MentionNotifying

      before_action :set_current_team
      before_action :set_issue

      def index
        comments = @issue.comments.top_level.includes(:user, replies: :user).order(:created_at)
        render json: comments.map { |c| CommentSerializer.new(c).as_json }
      end

      def create
        @comment = @issue.comments.new(comment_params)
        @comment.user = Current.user

        if @comment.save
          IssueReferenceService.call(
            source_issue: @issue,
            text: @comment.body,
            source_type: 'comment',
            user: Current.user
          )
          NotificationService.call(issue: @issue, actor: Current.user, action: 'commented', comment: @comment)
          notify_mentions_on(@issue, text: @comment.body, comment: @comment)

          render json: CommentSerializer.new(@comment).as_json, status: :created
        else
          render_validation_errors(@comment)
        end
      end

      private

      def set_issue
        @issue = current_team.issues.find(params[:issue_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found
      end

      def comment_params
        params.require(:comment).permit(:body, :parent_id)
      end
    end
  end
end
