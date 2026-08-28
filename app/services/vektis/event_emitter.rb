require 'active_support/core_ext/digest/uuid'
require 'json'
require 'securerandom'

# The server-side emit seam for VEKTIS analytics (VEK-583).
#
# Domain code calls this; nothing in app/ builds an event hash or touches Vektis::ApiClient
# directly. It is the exact mirror of app/javascript/vektis.js — read that file alongside this
# one, because the same three jobs apply and neither belongs in a call site:
#
# 1. properties.source = "server" is mandatory on every event (taxonomy §5.1) and is the only
#    field that makes server and browser events separable in analysis today (VEK-590). Stamping
#    it here — last, so a call site cannot override it — is what makes "no exceptions" true.
# 2. Nothing analytics does may surface to a user or roll back a transaction. Every path returns
#    nil and swallows, with one deliberate exception: in development and test a bad call site
#    raises, so taxonomy drift fails in CI instead of becoming a silent 400 months later.
# 3. event_id and timestamp are generated HERE, once, and carried through every retry. vanalytics
#    dedupes on (organization_id, event_id), so a UUID regenerated in the job would produce
#    duplicate rows on every redelivery — invisibly. Stamping the timestamp at emit time likewise
#    keeps a backed-up queue from misattributing when the action happened.
#
# Delivery is off-request via VektisEventJob. Nothing in here makes an HTTP call.
module Vektis
  class EventEmitter
    class InvalidEvent < StandardError; end

    class << self
      # feature.used — the user completed the thing the feature exists to do (§2). It is the only
      # event type with a server-side call site: session.active and customer.identified are the
      # browser's (§3.1, §3.2), feature.first_use is not emitted at all (§3.3), and every server
      # row in the §4 catalog is `used`.
      #
      # Pass `event_id:` for webhook-originated events, where it must be derived deterministically
      # from the delivery so a provider retry dedupes rather than duplicating (§8).
      def feature(feature_id, action, properties: {}, user_id: nil, event_id: nil)
        emit(event_type: 'feature.used', feature_id: feature_id, action: action,
             properties: properties, user_id: user_id, event_id: event_id)
      end

      # Integration-originated events (VEK-585) — inbound webhook deliveries, and the outbound API
      # calls the integrations make. Everything the browser cannot see by definition.
      #
      # These differ from .feature in exactly two ways, and both are why this wrapper exists rather
      # than every call site remembering them:
      #
      # 1. `key` is the caller's EXISTING idempotency handle — a provider delivery guid inbound, the
      #    job's own idempotency key outbound. Providers retry and vanalytics dedupes on
      #    (organization_id, event_id), so a random UUIDv4 would file a redelivery as new activity.
      # 2. `key` takes an array when one delivery legitimately produces the same (feature_id, action)
      #    more than once (§8, as amended by this ticket) — a merged PR closing three issues is
      #    three completions, not one, so the record id joins the key. It is hashed into the id and
      #    never shipped, which is what keeps §6's raw-record-ID ban intact.
      #
      # `via` is explicit rather than assumed. The server genuinely observes origin — a session
      # request, a background job and an HMAC-verified delivery are structurally different things —
      # which is not the input modality VEK-584 correctly refused to guess at.
      def integration(feature_id, action, provider:, via:, key:, properties: {})
        feature(feature_id, action,
                properties: properties.merge(provider: provider, via: via),
                event_id: integration_event_id(provider, key, feature_id, action))
      end

      def emit(event_type:, feature_id: nil, action: nil, properties: {}, user_id: nil, event_id: nil)
        # Free when the kill switch is off in production. Development and test still build and
        # validate so a bad call site is caught even with analytics disabled — which is the normal
        # CI configuration, and would otherwise be the one place drift could never be seen.
        return unless Vektis.enabled? || Rails.env.local?

        event = build(event_type: event_type, feature_id: feature_id, action: action,
                      properties: properties, user_id: user_id, event_id: event_id)
        reject!(event)
        audit(event)
        # Checked here rather than in the job so nothing accumulates in the queue while off.
        return unless Vektis.enabled?

        enqueue(event)
        nil
      rescue InvalidEvent => e
        raise if Rails.env.local?

        Rails.logger.error("Vektis::EventEmitter dropped invalid event: #{e.message}")
        nil
      rescue StandardError => e
        # The boundary. An analytics bug must never be a user-visible one.
        Rails.logger.error("Vektis::EventEmitter swallowed #{e.class}: #{e.message}")
        nil
      end

      private

      # A blank key degrades to the random UUIDv4 .feature would have used anyway. Losing dedupe on
      # one event is a cost worth paying; dropping it, or raising into a webhook response, is not —
      # GitHub retries on non-2xx and would turn an analytics fault into a redelivery storm.
      # Every component must be present. A partial key is not an idempotency key — a missing
      # delivery guid with a present subscription id would quietly collapse every future delivery
      # for that subscription onto one event_id, which is worse than not deduping at all.
      def integration_event_id(provider, key, feature_id, action)
        parts = Array(key).map(&:to_s)
        if parts.empty? || parts.any?(&:blank?)
          Rails.logger.warn("Vektis::EventEmitter #{feature_id}/#{action} has no idempotency key; " \
                            'falling back to a random event_id')
          return nil
        end

        Digest::UUID.uuid_v5(Taxonomy::EVENT_ID_NAMESPACE,
                             [provider, *parts, feature_id, action].join(':'))
      end

      # String keys throughout: ActiveJob round-trips them verbatim (a symbol-keyed hash picks up
      # an _aj_symbol_keys wrapper), so the queued payload is literally the wire shape and the
      # byte check below measures the same bytes Vektis::ApiClient will send.
      def build(event_type:, feature_id:, action:, properties:, user_id:, event_id:)
        {
          'event_id' => event_id.presence || SecureRandom.uuid, # v4 — satisfies z.string().uuid()
          'event_type' => event_type.to_s,
          'customer_id' => Vektis.customer_id,
          'feature_id' => feature_id.presence&.to_s,
          'user_id' => resolved_user_id(user_id),
          'action' => action.presence&.to_s,
          'properties' => scalar_properties(properties),
          'timestamp' => Time.current.utc.iso8601
        }.compact # load-bearing: the schema's optional fields reject an explicit null
      end

      # mtasks User#id as a string (§6.2) — never an email, never a name. Webhook and job paths
      # have no Current.user, so absence is automatic there, and absence is correct rather than a
      # defect to paper over.
      def resolved_user_id(user_id)
        (user_id.presence || Current.user&.id)&.to_s
      end

      def scalar_properties(properties)
        cleaned = {}

        (properties || {}).each do |key, value|
          scalar = scalar_value(value)
          cleaned[key.to_s] = scalar unless scalar.nil?
        end

        cleaned['source'] = 'server' # stamped last: §5.1 has no exceptions
        cleaned
      end

      # properties is Record<string, string | number | boolean>. A single nil makes the server 400
      # the batch, and a 400 is a drop with no retry — one mistyped lookup would take every event
      # batched alongside it down too. Drop bad values rather than ship them, exactly as vektis.js
      # does. Symbols are coerced rather than dropped: Ruby call sites will write `via: :webhook`,
      # and JSON.generate would have stringified it anyway.
      def scalar_value(value)
        case value
        when String, true, false then value
        when Symbol then value.to_s
        when Numeric then value if value.to_f.finite? # NaN/Infinity are not valid JSON
        end
      end

      # The wire rules. A violation here is a guaranteed 400, which drops the whole batch.
      def reject!(event)
        type = event['event_type']
        invalid!("unknown event_type #{type.inspect}") unless Taxonomy::EVENT_TYPES.include?(type)
        invalid!('feature_id is required for feature.* events') if missing_feature_id?(event, type)
        invalid!('customer_id is blank — check VEKTIS_CUSTOMER_ID') if event['customer_id'].blank?
        reject_field_lengths!(event)
        reject_properties!(event)
      end

      def missing_feature_id?(event, type)
        Taxonomy::FEATURE_TYPES.include?(type) && event['feature_id'].blank?
      end

      def reject_field_lengths!(event)
        max = Taxonomy::MAX_FIELD_LENGTH

        %w[customer_id feature_id user_id action].each do |field|
          next if event[field].to_s.length <= max

          invalid!("#{field} exceeds #{max} characters")
        end
      end

      def reject_properties!(event)
        properties = event['properties']
        keys = Taxonomy::MAX_PROPERTY_KEYS
        invalid!("properties has #{properties.size} keys, over #{keys}") if properties.size > keys

        properties.each { |key, value| reject_property!(key, value) }

        bytes = JSON.generate(event).bytesize
        return if bytes <= Taxonomy::MAX_EVENT_BYTES

        invalid!("event is #{bytes} bytes, over the #{Taxonomy::MAX_EVENT_BYTES} byte cap")
      end

      def reject_property!(key, value)
        max_key = Taxonomy::MAX_PROPERTY_KEY_LENGTH
        max_value = Taxonomy::MAX_STRING_VALUE_LENGTH
        invalid!("property key #{key.inspect} is over #{max_key} chars") if key.length > max_key
        return unless value.is_a?(String) && value.length > max_value

        invalid!("property #{key.inspect} is over #{max_value} chars")
      end

      # Taxonomy conformance, as opposed to schema conformance. Locally any drift raises, which is
      # where a new call site gets written and where the fix belongs.
      #
      # In production the two kinds of drift are NOT treated alike, because only one of them can
      # carry PII (VEK-587):
      #
      # - An unknown feature_id or action means OUR registry is stale, not that the caller's data is
      #   bad. A slug is a literal at every call site and cannot contain user content, so the event
      #   ships and the mismatch is logged — losing the data would be the worse outcome.
      # - An unregistered property key is the one way free text reaches the wire. §6's PII ban is
      #   only "mechanical" (taxonomy.rb §5.2) if the wire code enforces it rather than trusting CI
      #   to have covered the call site, so the offending keys are STRIPPED and the rest of the
      #   event still ships. properties is stored verbatim in impact_events.properties and there is
      #   no delete path, so shipping first and auditing later is not recoverable.
      def audit(event)
        problems = catalog_problems(event) + strip_unregistered_properties!(event)
        return if problems.empty?

        message = "taxonomy drift: #{problems.join('; ')}"
        raise InvalidEvent, message if Rails.env.local?

        Rails.logger.warn("Vektis::EventEmitter #{message}")
      end

      def catalog_problems(event)
        problems = []
        type = event['event_type']
        problems << "#{type} has no server-side call site (§3, §9)" unless type == 'feature.used'

        feature_id = event['feature_id']
        actions = Taxonomy::CATALOG[feature_id]
        return problems << "#{feature_id.inspect} is not a server-owned feature_id" if actions.nil?

        action = event['action']
        problems << "#{action.inspect} is not a #{feature_id} action" unless actions.include?(action)
        problems
      end

      # Mutates `event` on purpose: the caller raises on this in development and test, so the strip
      # only ever takes effect in production — exactly where an unreviewed key would otherwise leak.
      def strip_unregistered_properties!(event)
        unknown = event['properties'].keys - Taxonomy::PROPERTY_KEYS
        return [] if unknown.empty?

        unknown.each { |key| event['properties'].delete(key) }
        ["#{unknown.join(', ')} outside the closed property registry (§5.2), dropped"]
      end

      # Never emit for a write that rolled back. after_all_transactions_commit yields immediately
      # when no transaction is open, fires after the outermost commit when one is, and never fires
      # on rollback — the after_create_commit semantics every call site would otherwise have to
      # remember (cf. Issue#enqueue_velocity_recalculation!).
      #
      # The block runs outside emit's rescue, so it carries its own: a queue-database failure at
      # commit time must not raise into the caller's transaction.
      def enqueue(event)
        ActiveRecord.after_all_transactions_commit do
          VektisEventJob.perform_later(event)
        rescue StandardError => e
          Rails.logger.error("Vektis::EventEmitter failed to enqueue: #{e.class}: #{e.message}")
        end
      end

      def invalid!(message)
        raise InvalidEvent, message
      end
    end
  end
end
