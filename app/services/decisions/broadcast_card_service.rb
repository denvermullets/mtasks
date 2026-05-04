module Decisions
  class BroadcastCardService < Service
    def initialize(project:)
      @project = project
    end

    def call
      return unless @project

      Turbo::StreamsChannel.broadcast_replace_later_to(
        "project_#{@project.id}_decisions",
        target: "project_#{@project.id}_decisions_card",
        partial: 'projects/decisions_card_body',
        locals: { project: @project }
      )
    end
  end
end
