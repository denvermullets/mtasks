class CommentsController < ApplicationController
  before_action :require_team!
  before_action :set_issue
  before_action :set_comment, only: :destroy
  before_action :authorize_comment_deletion!, only: :destroy

  def create
    @comment = @issue.comments.new(comment_params)
    @comment.user = Current.user

    if @comment.save
      notify_comment_created
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to team_issue_path(@issue.team, @issue), notice: 'Comment was successfully created.' }
      end
    else
      respond_to_with_comment_errors
    end
  end

  def destroy
    @comment.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to team_issue_path(@issue.team, @issue), notice: 'Comment was successfully deleted.' }
    end
  end

  private

  def set_issue
    @issue = Issue.find(params[:issue_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'Issue not found.'
  end

  def set_comment
    @comment = @issue.comments.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to team_issue_path(@issue.team, @issue), alert: 'Comment not found.'
  end

  def authorize_comment_deletion!
    return if Current.user.admin? || @comment.user == Current.user

    redirect_to team_issue_path(@issue.team, @issue), alert: 'You do not have permission to delete this comment.'
  end

  def respond_to_with_comment_errors
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          'comment_form',
          partial: 'comments/form',
          locals: { issue: @issue, comment: @comment }
        )
      end
      format.html { redirect_to team_issue_path(@issue.team, @issue), alert: 'Failed to create comment.' }
    end
  end

  def notify_comment_created
    NotificationService.call(issue: @issue, actor: Current.user, action: 'commented', comment: @comment)
  end

  def comment_params
    params.require(:comment).permit(:body, :parent_id)
  end
end
