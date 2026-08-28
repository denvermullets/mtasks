module Discussion
  class CommentsController < ApplicationController
    include TeamScoped

    before_action :require_team!
    before_action :set_project
    before_action :set_comment, only: :push

    def create
      @comment = @project.comments.new(comment_params.merge(user: Current.user))

      if @comment.save
        track_comment_created
        push_result = maybe_push(@comment)
        broadcast_new_comment(@comment)
        render_create_success(push_result)
      else
        render_create_failure
      end
    end

    def push
      result = ::Discussion::PushCommentToChatService.call(comment: @comment)
      broadcast_comment_replace(@comment) if result.success?
      respond_to do |format|
        format.turbo_stream { render :push, locals: { push_result: result } }
        format.html do
          if result.success?
            redirect_to discussion_team_project_path(@project.team, @project),
                        notice: "Posted to ##{result.channel_name}"
          else
            redirect_to discussion_team_project_path(@project.team, @project), alert: result.error
          end
        end
      end
    end

    private

    # `tab` is the one surface-like field a server call site can honestly assert: the route
    # itself is the evidence.
    def track_comment_created
      track_feature('comment', 'create', entity: 'project', depth: @comment.depth, tab: 'discussion')
      files = uploaded_file_count(params.dig(:comment, :files))
      track_feature('issue-attachment', 'create', entity: 'comment', count: files) if files.positive?
    end

    def render_create_success(push_result)
      respond_to do |format|
        format.turbo_stream { render :create, locals: { push_result: push_result } }
        format.html do
          redirect_to discussion_team_project_path(@project.team, @project), notice: notice_for(push_result)
        end
      end
    end

    def render_create_failure
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity, locals: { push_result: nil } }
        format.html do
          redirect_to discussion_team_project_path(@project.team, @project),
                      alert: @comment.errors.full_messages.join(', ')
        end
      end
    end

    def maybe_push(comment)
      return nil unless ActiveModel::Type::Boolean.new.cast(params[:also_send_to_chat])

      ::Discussion::PushCommentToChatService.call(comment: comment)
    end

    def notice_for(push_result)
      base = 'Comment posted.'
      return base if push_result.nil?
      return "#{base} Posted to ##{push_result.channel_name}." if push_result.success?

      "#{base} (chat push failed: #{push_result.error})"
    end

    def broadcast_new_comment(comment)
      Turbo::StreamsChannel.broadcast_append_to(
        "project_#{@project.id}_discussion",
        target: 'discussion-stream',
        partial: 'projects/discussion_native_comment',
        locals: { comment: comment, project: @project }
      )
    end

    def broadcast_comment_replace(comment)
      Turbo::StreamsChannel.broadcast_replace_to(
        "project_#{@project.id}_discussion",
        target: ActionView::RecordIdentifier.dom_id(comment),
        partial: 'projects/discussion_native_comment',
        locals: { comment: comment, project: @project }
      )
    end

    def set_project
      @project = current_team.projects.find(params[:project_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to team_projects_path(current_team), alert: 'Project not found.'
    end

    def set_comment
      @comment = @project.comments.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to discussion_team_project_path(@project.team, @project), alert: 'Comment not found.'
    end

    def comment_params
      params.require(:comment).permit(:body, files: [])
    end
  end
end
