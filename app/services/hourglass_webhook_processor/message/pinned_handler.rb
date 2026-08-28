module HourglassWebhookProcessor
  module Message
    class PinnedHandler < BaseHandler
      def call
        return warn_missing_ids('message_id/channel_id') if message_id.blank? || channel_id.blank?

        cache = HourglassMessageCache.find_by(hourglass_message_id: message_id)
        return logger.info("pin for unknown message #{message_id}") unless cache

        link = find_link(cache.hourglass_channel_id)
        return log_orphan(cache.hourglass_channel_id) unless link

        apply_pin(cache, link)
      end

      private

      def log_orphan(channel_id)
        logger.info("pin orphan message #{message_id} (no active link for #{channel_id})")
      end

      def apply_pin(cache, link)
        pinned_at = parse_time(payload['pinned_at']) || Time.current
        pinned_by_email = payload.dig('pinned_by', 'email') || payload['pinned_by_email']
        cache.update!(pinned_at: pinned_at, pinned_by_email: pinned_by_email)

        upsert_decision(cache, link, pinned_at, pinned_by_email)
        broadcast_message(action: :replace, cache: cache, link: link)
        Decisions::BroadcastCardService.call(project: link.mtasks_project)
      end

      def upsert_decision(cache, link, pinned_at, pinned_by_email)
        existing = Decision.find_by(hourglass_message_id: cache.hourglass_message_id)
        resolved_user = resolve_pinned_by_user(pinned_by_email, link)

        return track_decision_recorded(create_decision(cache, link, pinned_at, resolved_user)) unless existing

        # A re-pin of a previously unpinned message is a decision being recorded again, so it
        # emits. Re-pinning one that is already active is a no-op restatement and must not.
        reactivated = existing.unpinned_at.present?
        existing.update!(
          unpinned_at: nil,
          pinned_at: pinned_at,
          pinned_by_user: resolved_user || existing.pinned_by_user
        )
        track_decision_recorded(existing) if reactivated
      end

      # The decision's *id* — never its body_snapshot, which is the pinned message verbatim and the
      # single largest PII risk on this surface (§6).
      def track_decision_recorded(decision)
        track_integration('decision', 'create', decision.id, entity: 'project', team: decision.team)
      end

      def create_decision(cache, link, pinned_at, resolved_user)
        Decision.create!(
          team: link.mtasks_project.team,
          project: link.mtasks_project,
          hourglass_message_id: cache.hourglass_message_id,
          pinned_at: pinned_at,
          pinned_by_user: resolved_user,
          body_snapshot: cache.body.to_s,
          idempotency_key: "pin:#{cache.hourglass_message_id}:#{pinned_at.utc.iso8601}"
        )
      end

      def resolve_pinned_by_user(email, link)
        return nil if email.blank?

        HourglassUserResolver.call(
          email: email,
          integration: link.hourglass_integration || integration,
          lazy_fetch: true
        ).user
      end
    end
  end
end
