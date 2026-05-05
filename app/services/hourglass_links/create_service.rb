module HourglassLinks
  class CreateService < Service
    Result = Struct.new(:link, :error, keyword_init: true)

    def initialize(project:, channel_id:, channel_name:, integration:, current_user:, notify_outbound: true)
      @project = project
      @channel_id = channel_id
      @channel_name = channel_name
      @integration = integration
      @current_user = current_user
      @notify_outbound = notify_outbound
    end

    def call
      link = HourglassLink.new(
        link_type: 'project_channel',
        team: @project.team,
        mtasks_project: @project,
        hourglass_channel_id: @channel_id,
        hourglass_channel_name: @channel_name,
        hourglass_integration: @integration,
        created_by_user: @current_user,
        status: 'active'
      )

      if link.save
        HourglassNotifyLinkCreatedJob.perform_later(link.id) if @notify_outbound
        broadcast_badge
        Result.new(link: link)
      else
        Result.new(link: link, error: link.errors.full_messages.to_sentence)
      end
    end

    private

    def broadcast_badge
      @project.association(:hourglass_channel_link).reset
      Turbo::StreamsChannel.broadcast_replace_to(
        "project_#{@project.id}",
        target: "project_channel_badge_#{@project.id}",
        partial: 'projects/channel_link_badge',
        locals: { project: @project }
      )
    end
  end
end
