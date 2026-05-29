class DiscussionStreamService < Service
  Item = Struct.new(:kind, :record, :sort_at)

  def initialize(project: nil, channel_link: nil, issue: nil, issue_thread_link: nil)
    @project = project
    @channel_link = channel_link || project&.hourglass_channel_link
    @issue = issue
    @issue_thread_link = issue_thread_link
  end

  def call
    (hourglass_items + native_items).sort_by(&:sort_at)
  end

  private

  def hourglass_items
    scope = hourglass_scope
    return [] unless scope

    scope.not_deleted.order(:posted_at).map { |m| Item.new(:hourglass, m, m.posted_at) }
  end

  def hourglass_scope
    if @issue_thread_link
      HourglassMessageCache.where(
        'hourglass_thread_id = :tid OR hourglass_message_id = :tid',
        tid: @issue_thread_link.hourglass_thread_id
      )
    elsif @channel_link
      HourglassMessageCache.where(hourglass_channel_id: @channel_link.hourglass_channel_id)
    end
  end

  def native_items
    base = native_comment_scope
    return [] unless base

    base.top_level.includes(:user).order(:created_at).map { |c| Item.new(:native, c, c.created_at) }
  end

  def native_comment_scope
    if @issue
      Comment.where(issue_id: @issue.id)
    elsif @project
      Comment.where(project_id: @project.id)
    end
  end
end
