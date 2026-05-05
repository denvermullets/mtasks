module HourglassLinks
  class DestroyService < Service
    Result = Struct.new(:error, keyword_init: true)

    def initialize(link:, notify_outbound: true)
      @link = link
      @notify_outbound = notify_outbound
    end

    def call
      payload = build_payload
      job_class = job_for(@link)
      project = @link.mtasks_project if @link.project_channel?

      @link.destroy!
      job_class&.perform_later(payload) if @notify_outbound
      broadcast_badge(project) if project
      Result.new(error: nil)
    rescue ActiveRecord::RecordNotDestroyed => e
      Result.new(error: e.message)
    end

    private

    def build_payload
      common = { integration_id: @link.hourglass_integration_id }
      if @link.issue_thread?
        common.merge(
          mtasks_issue_id: @link.mtasks_issue_id,
          hourglass_thread_id: @link.hourglass_thread_id
        )
      else
        common.merge(
          channel_id: @link.hourglass_channel_id,
          project_id: @link.mtasks_project_id
        )
      end
    end

    def job_for(link)
      link.issue_thread? ? HourglassNotifyThreadLinkDestroyedJob : HourglassNotifyLinkDestroyedJob
    end

    def broadcast_badge(project)
      project.association(:hourglass_channel_link).reset
      Turbo::StreamsChannel.broadcast_replace_to(
        "project_#{project.id}",
        target: "project_channel_badge_#{project.id}",
        partial: 'projects/channel_link_badge',
        locals: { project: project }
      )
    end
  end
end
