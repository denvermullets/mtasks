module Discussion
  class IssueCommentsController < ApplicationController
    include TeamScoped

    before_action :require_team!
    before_action :set_issue

    def create
      @comment = @issue.comments.new(comment_params.merge(user: Current.user))

      if @comment.save
        track_comment_created
        push_result = maybe_push(@comment)
        broadcast_new_comment(@comment)
        render_create_success(push_result)
      else
        render_create_failure
      end
    end

    private

    # `tab` is the one surface-like field a server call site can honestly assert: the route
    # itself is the evidence.
    def track_comment_created
      track_feature('comment', 'create', entity: 'issue', depth: @comment.depth, tab: 'discussion')
      files = uploaded_file_count(params.dig(:comment, :files))
      track_feature('issue-attachment', 'create', entity: 'comment', count: files) if files.positive?
    end

    def render_create_success(push_result)
      respond_to do |format|
        format.turbo_stream { render :create, locals: { push_result: push_result } }
        format.html do
          redirect_to team_issue_path(@issue.team, @issue), notice: notice_for(push_result)
        end
      end
    end

    def render_create_failure
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity, locals: { push_result: nil } }
        format.html do
          redirect_to team_issue_path(@issue.team, @issue),
                      alert: @comment.errors.full_messages.join(', ')
        end
      end
    end

    def maybe_push(comment)
      return nil unless ActiveModel::Type::Boolean.new.cast(params[:also_send_to_chat])

      ::Discussion::PushCommentToChatService.call(comment: comment, link: thread_link)
    end

    def thread_link
      @thread_link ||= HourglassLink.for_issue(@issue).active.first
    end

    def notice_for(push_result)
      base = 'Comment posted.'
      return base if push_result.nil?
      return "#{base} Posted to thread." if push_result.success?

      "#{base} (chat push failed: #{push_result.error})"
    end

    def broadcast_new_comment(comment)
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
      redirect_to team_issues_path(current_team), alert: 'Issue not found.'
    end

    def comment_params
      params.require(:comment).permit(:body, files: [])
    end
  end
end
