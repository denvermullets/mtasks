module HourglassWebhookProcessor
  module Message
    class UpdatedHandler < BaseHandler
      def call
        return warn_missing_ids('message_id/channel_id') if message_id.blank? || channel_id.blank?
        return if find_loop_guard_comment(message_id)

        cache = HourglassMessageCache.find_by(hourglass_message_id: message_id)
        return CreatedHandler.call(delivery, integration) if cache.nil?

        apply_update(cache)

        link = find_link(cache.hourglass_channel_id)
        broadcast_message(action: :replace, cache: cache, link: link) if link
      end

      private

      def apply_update(cache)
        cache.update!(
          body: payload['body'].to_s,
          edited_at: parse_time(payload['edited_at']) || Time.current,
          payload: payload
        )
      end
    end
  end
end
