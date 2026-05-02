class DiscussionStreamService < Service
  Item = Struct.new(:kind, :record, :sort_at)

  def initialize(project:, channel_link: nil)
    @project = project
    @channel_link = channel_link || project.hourglass_channel_link
  end

  def call
    (hourglass_items + native_items).sort_by(&:sort_at)
  end

  private

  def hourglass_items
    return [] unless @channel_link

    HourglassMessageCache
      .where(hourglass_channel_id: @channel_link.hourglass_channel_id)
      .not_deleted
      .order(:posted_at)
      .map { |m| Item.new(:hourglass, m, m.posted_at) }
  end

  def native_items
    Comment
      .where(project_id: @project.id)
      .top_level
      .includes(:user)
      .order(:created_at)
      .map { |c| Item.new(:native, c, c.created_at) }
  end
end
