module HourglassWebhookProcessor
  module Message
    class UnpinnedHandler < BaseHandler
      def call
        return warn_missing_ids('message_id') if message_id.blank?

        cache = HourglassMessageCache.find_by(hourglass_message_id: message_id)
        return logger.info("unpin for unknown message #{message_id}") unless cache

        clear_cache_pin(cache)
        link = find_link(cache.hourglass_channel_id)
        broadcast_message(action: :replace, cache: cache, link: link) if link
        unpin_decision(link)
      end

      private

      def clear_cache_pin(cache)
        return if cache.pinned_at.blank?

        cache.update!(pinned_at: nil, pinned_by_email: nil)
      end

      def unpin_decision(link)
        decision = Decision.active.find_by(hourglass_message_id: message_id)
        return unless decision

        decision.update!(unpinned_at: parse_time(payload['unpinned_at']) || Time.current)
        track_integration('decision', 'delete', decision.id, entity: 'project')
        Decisions::BroadcastCardService.call(project: link.mtasks_project) if link
      end
    end
  end
end
