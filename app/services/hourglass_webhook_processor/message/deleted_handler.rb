module HourglassWebhookProcessor
  module Message
    class DeletedHandler < BaseHandler
      def call
        return warn_missing_ids('message_id') if message_id.blank?
        return if find_loop_guard_comment(message_id)

        cache = HourglassMessageCache.find_by(hourglass_message_id: message_id)
        return logger.info("delete for unknown message #{message_id}") unless cache

        cache.update!(deleted_at: Time.current) if cache.deleted_at.blank?
        link = find_link(cache.hourglass_channel_id)
        broadcast_message(action: :replace, cache: cache, link: link) if link
      end
    end
  end
end
