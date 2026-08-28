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

    # The VEK-585 emit seam for the handlers. Every handler runs inside a signature-verified
    # delivery with no Current.user, so `user_id` is absent by construction and the delivery guid
    # is what makes a redelivery dedupe at vanalytics rather than double count (§8). `subject`
    # joins the key because one delivery can act on more than one record.
    def track_integration(feature_id, action, subject, **properties)
      Vektis::EventEmitter.integration(
        feature_id, action,
        provider: 'hourglass', via: 'webhook',
        key: [delivery.delivery_id, subject],
        properties: properties.compact
      )
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
      broadcast_to_project(action, cache, link)
      broadcast_to_issue_threads(action, cache)
    end

    def broadcast_to_project(action, cache, link)
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

    def broadcast_to_issue_threads(action, cache)
      thread_ids = [cache.hourglass_thread_id, cache.hourglass_message_id].compact.uniq
      return if thread_ids.empty?

      HourglassLink.issue_thread.active.where(hourglass_thread_id: thread_ids).each do |thread_link|
        broadcast_to_issue_thread(action, cache, thread_link)
      end
    end

    def broadcast_to_issue_thread(action, cache, thread_link)
      issue = thread_link.mtasks_issue
      return unless issue

      stream = "issue_#{issue.id}_discussion"
      common = {
        partial: 'projects/discussion_message',
        locals: { message: cache, team: issue.team, channel_link: thread_link }
      }
      if action == :append
        Turbo::StreamsChannel.broadcast_append_later_to(
          stream, target: "issue_discussion_stream_#{issue.id}", **common
        )
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
