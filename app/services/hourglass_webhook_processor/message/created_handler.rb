module HourglassWebhookProcessor
  module Message
    class CreatedHandler < BaseHandler
      def call
        return warn_missing_ids('message_id/channel_id') if message_id.blank? || channel_id.blank?
        return if loop_guard_handled?

        link = find_link(channel_id)
        return logger.info("orphan message #{message_id} (no active link for #{channel_id})") unless link

        prime_user_map(link)
        cache, was_new = upsert_cache
        broadcast_message(action: was_new ? :append : :replace, cache: cache, link: link)
      end

      private

      def loop_guard_handled?
        comment = find_loop_guard_comment(message_id)
        return false unless comment

        stamp_pushed_at(comment)
        true
      end

      def upsert_cache
        cache = HourglassMessageCache.find_or_initialize_by(hourglass_message_id: message_id)
        was_new = cache.new_record?
        cache.assign_attributes(cache_attributes)
        cache.save!
        [cache, was_new]
      end

      # rubocop:disable Metrics/AbcSize
      def cache_attributes
        {
          hourglass_channel_id: channel_id,
          hourglass_thread_id: payload['thread_id'],
          hourglass_user_id: author['user_id'] || author['id'],
          author_email: author['email'],
          author_display_name: author['display_name'] || author['name'],
          body: payload['body'].to_s,
          message_type: payload['message_type'].presence || 'chat',
          posted_at: parse_time(payload['posted_at']) || Time.current,
          edited_at: parse_time(payload['edited_at']),
          payload: payload,
          source: 'webhook'
        }
      end
      # rubocop:enable Metrics/AbcSize

      def author
        @author ||= payload['author'].is_a?(Hash) ? payload['author'] : {}
      end

      def prime_user_map(link)
        return if author['email'].blank?

        HourglassUserResolver.call(
          email: author['email'],
          hourglass_user_id: author['user_id'] || author['id'],
          display_name: author['display_name'] || author['name'],
          integration: link.hourglass_integration || integration,
          lazy_fetch: true
        )
      end
    end
  end
end
