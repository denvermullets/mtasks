module HourglassWebhookProcessor
  class BaseHandler < Service
    def initialize(delivery, integration)
      @delivery = delivery
      @integration = integration
    end

    private

    attr_reader :delivery, :integration

    def payload
      @payload ||= delivery.payload || {}
    end

    def logger
      Rails.logger
    end

    def find_link(channel_id)
      HourglassLink.project_channel.active.find_by(
        hourglass_channel_id: channel_id,
        hourglass_integration_id: integration.id
      )
    end

    def message_id
      payload['message_id'] || payload.dig('message', 'id')
    end

    def channel_id
      payload['channel_id'] || payload.dig('channel', 'id')
    end

    def warn_missing_ids(missing)
      logger.warn(
        "#{self.class.name} missing #{missing} (delivery=#{delivery.delivery_id})"
      )
    end

    def broadcast_message(action:, cache:, link:)
      stream = "project_#{link.mtasks_project_id}_discussion"
      common = {
        partial: 'projects/discussion_message',
        locals: { message: cache, project: link.mtasks_project, channel_link: link }
      }
      if action == :append
        Turbo::StreamsChannel.broadcast_append_later_to(stream, target: 'discussion-stream', **common)
      else
        Turbo::StreamsChannel.broadcast_replace_later_to(
          stream, target: ActionView::RecordIdentifier.dom_id(cache), **common
        )
      end
    end

    def find_loop_guard_comment(message_id)
      Comment.find_by(pushed_to_hourglass_message_id: message_id)
    end

    def stamp_pushed_at(comment)
      return if comment.pushed_to_hourglass_at.present?

      comment.update!(pushed_to_hourglass_at: Time.current)
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
