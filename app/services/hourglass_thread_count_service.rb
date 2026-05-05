class HourglassThreadCountService < Service
  def initialize(issues:, user:)
    @issues = Array(issues)
    @user = user
  end

  def call
    return {} if @issues.empty?

    links = active_issue_thread_links
    return {} if links.empty?

    build_counts(links)
  end

  private

  def active_issue_thread_links
    HourglassLink.issue_thread.active.where(mtasks_issue_id: @issues.map(&:id))
  end

  def build_counts(links)
    link_by_issue = links.index_by(&:mtasks_issue_id)
    messages = messages_by_thread(links)
    last_read = last_read_by_link(links)

    @issues.each_with_object({}) do |issue, result|
      link = link_by_issue[issue.id]
      next unless link

      result[issue.id] = count_for(link, messages, last_read)
    end
  end

  def messages_by_thread(links)
    thread_ids = links.map(&:hourglass_thread_id)
    HourglassMessageCache
      .not_deleted
      .where('hourglass_thread_id IN (:ids) OR hourglass_message_id IN (:ids)', ids: thread_ids)
      .pluck(:hourglass_thread_id, :hourglass_message_id, :posted_at)
      .group_by { |tid, mid, _| thread_ids.include?(tid) ? tid : mid }
  end

  def last_read_by_link(links)
    HourglassLinkReadState
      .where(user_id: @user&.id, hourglass_link_id: links.map(&:id))
      .pluck(:hourglass_link_id, :last_read_at)
      .to_h
  end

  def count_for(link, messages_by_thread, last_read_by_link)
    messages = messages_by_thread[link.hourglass_thread_id] || []
    last_read = last_read_by_link[link.id]
    unread = last_read ? messages.count { |_, _, posted_at| posted_at > last_read } : messages.size
    { link_id: link.id, total: messages.size, unread: unread }
  end
end
