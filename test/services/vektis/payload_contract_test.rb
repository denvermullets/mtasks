require 'test_helper'

module Vektis
  # The payload contract (VEK-586): every event mtasks emits has to satisfy
  # @vektis-io/events-schema@1.1.0, which vanalytics validates with the real Zod schema before it
  # will accept a batch. A breach is a 400, and a 400 drops the whole batch with no retry.
  #
  # SOURCE OF TRUTH: ../events-schema/src/index.ts (trackingEventSchema / trackEventsSchema).
  # There is no JSON Schema artifact and no language-neutral export, so the rules below are a hand
  # transcription. Editing the Zod schema means editing this file in the same change — nothing
  # mechanical will catch the drift.
  #
  # The limits here are deliberately written as literals rather than read from Vektis::Taxonomy.
  # Vektis::EventEmitter validates *using* Taxonomy, so asserting against Taxonomy would only prove
  # the emitter agrees with itself. The `taxonomy still matches the schema` test at the bottom
  # compares the two transcriptions, and that comparison is the only drift detector we have.
  #
  # Two known, intentional divergences from Zod:
  #   1. Taxonomy::MAX_EVENT_BYTES applies 8192 to the whole event in *bytes*; Zod applies 8192 to
  #      `properties` alone in JS string *length*. Ruby is strictly stricter, which is safe.
  #   2. Zod's .object() strips unknown top-level keys instead of rejecting them, so an extra field
  #      is silent data loss rather than a 400. Asserted here as if it were fatal, because losing a
  #      field quietly is worse than being told about it.
  class PayloadContractTest < ActiveJob::TestCase
    include VektisEventTestHelper

    # --- the contract, transcribed from events-schema/src/index.ts ------------------------------

    # z.string().uuid() — any RFC 4122 version, correct variant bits.
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

    # z.string().datetime({ offset: true }) — the offset is required, so a naive local time fails.
    ISO8601_WITH_OFFSET = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})\z/

    SCHEMA_EVENT_TYPES = %w[feature.used feature.engagement feature.first_use
                            session.active customer.identified].freeze
    SCHEMA_FEATURE_TYPES = %w[feature.used feature.engagement feature.first_use].freeze

    # The eight keys the object declares. Anything else is stripped in transit.
    SCHEMA_FIELDS = %w[event_id event_type feature_id customer_id user_id action
                       properties timestamp].freeze

    SCHEMA_MAX_STRING = 255 # feature_id / customer_id / user_id / action
    SCHEMA_MAX_PROPERTY_KEYS = 50
    SCHEMA_MAX_PROPERTY_KEY = 64
    SCHEMA_MAX_PROPERTY_VALUE = 1024
    SCHEMA_MAX_PROPERTIES_JSON = 8192
    SCHEMA_MAX_BATCH = 100
    SCHEMA_MAX_BODY_BYTES = 512 * 1024

    SCHEMA_PAST_WINDOW = 7.days
    SCHEMA_FUTURE_WINDOW = 1.hour

    # Registered property keys (Taxonomy::PROPERTY_KEYS) — anything outside raises in test env, so
    # the corpus loop stays inside the registry.
    CORPUS_PROPERTIES = { entity: 'issue', count: 1 }.freeze

    setup do
      enable_vektis!
      clear_enqueued_jobs
    end

    teardown do
      restore_vektis_env!
      Current.user = nil
    end

    # --- the assertion under test ---------------------------------------------------------------

    def assert_schema_conformant(event, context = nil)
      label = context || event['feature_id']
      assert_schema_identity(event, label)
      assert_schema_optional_strings(event, label)
      assert_schema_properties(event, label)
      assert_schema_timestamp(event, label)
      assert_no_explicit_nulls(event, label)
    end

    def assert_schema_identity(event, label)
      assert_match UUID, event['event_id'].to_s, "#{label}: event_id is not a UUID"
      assert_includes SCHEMA_EVENT_TYPES, event['event_type'], "#{label}: unknown event_type"
      assert_bounded_string(event['customer_id'], "#{label}: customer_id")

      return unless SCHEMA_FEATURE_TYPES.include?(event['event_type'])

      assert_bounded_string(event['feature_id'], "#{label}: feature_id is required for feature.*")
    end

    def assert_schema_optional_strings(event, label)
      # Optional, but capped when present — and the key must be absent rather than null.
      assert_empty event.keys - SCHEMA_FIELDS, "#{label}: keys outside the schema are stripped in transit"

      %w[user_id action feature_id].each do |field|
        next unless event.key?(field)

        assert_operator event[field].to_s.length, :<=, SCHEMA_MAX_STRING, "#{label}: #{field} over #{SCHEMA_MAX_STRING}"
      end
    end

    def assert_schema_properties(event, label)
      properties = event.fetch('properties', {})
      assert_kind_of Hash, properties, "#{label}: properties must be an object"
      assert_operator properties.size, :<=, SCHEMA_MAX_PROPERTY_KEYS, "#{label}: over #{SCHEMA_MAX_PROPERTY_KEYS} keys"

      properties.each do |key, value|
        assert_operator key.length, :<=, SCHEMA_MAX_PROPERTY_KEY, "#{label}: property key #{key.inspect} too long"
        assert schema_scalar?(value), "#{label}: property #{key.inspect} is #{value.class}, not a flat scalar"
        next unless value.is_a?(String)

        assert_operator value.length, :<=, SCHEMA_MAX_PROPERTY_VALUE, "#{label}: property #{key.inspect} too long"
      end

      # Zod measures JSON.stringify(properties).length — JS string length, so .size, not .bytesize.
      assert_operator JSON.generate(properties).size, :<=, SCHEMA_MAX_PROPERTIES_JSON, "#{label}: properties over 8KB"
    end

    def assert_schema_timestamp(event, label)
      return unless event.key?('timestamp')

      assert_match ISO8601_WITH_OFFSET, event['timestamp'].to_s, "#{label}: timestamp carries no offset"

      stamped = Time.iso8601(event['timestamp'])
      assert_operator stamped, :>=, SCHEMA_PAST_WINDOW.ago, "#{label}: timestamp is outside the ingest window"
      assert_operator stamped, :<=, SCHEMA_FUTURE_WINDOW.from_now, "#{label}: timestamp is too far in the future"
    end

    # Every field but event_id/event_type/customer_id is .optional(), and a Zod optional rejects an
    # explicit null — the key has to be missing, which is what build's .compact guarantees.
    def assert_no_explicit_nulls(event, label)
      assert_empty event.select { |_key, value| value.nil? }, "#{label}: an explicit null 400s the batch"
      assert_empty event.fetch('properties', {}).select { |_key, value| value.nil? }, "#{label}: null property"
    end

    # properties is Record<string, string | number | boolean> — no nested objects, no arrays.
    def schema_scalar?(value)
      value.is_a?(String) || value.is_a?(Numeric) || [true, false].include?(value)
    end

    def assert_bounded_string(value, label)
      assert value.present?, "#{label} is blank"
      assert_operator value.length, :>=, 1, "#{label} is empty"
      assert_operator value.length, :<=, SCHEMA_MAX_STRING, "#{label} is over #{SCHEMA_MAX_STRING}"
    end

    # --- the corpus -----------------------------------------------------------------------------

    test 'every catalogued (feature_id, action) pair emits a schema-conformant payload' do
      Taxonomy::CATALOG.each do |feature_id, actions|
        actions.each { |action| EventEmitter.feature(feature_id, action, properties: CORPUS_PROPERTIES) }
      end

      # Guards the loop itself: a new catalog entry that fails to emit would otherwise pass silently.
      assert_equal Taxonomy::CATALOG.values.sum(&:size), emitted.size
      emitted.each { |event| assert_schema_conformant(event, "#{event['feature_id']}/#{event['action']}") }
    end

    test 'the corpus covers the whole catalog, pair for pair' do
      Taxonomy::CATALOG.each do |feature_id, actions|
        actions.each { |action| EventEmitter.feature(feature_id, action, properties: CORPUS_PROPERTIES) }
      end

      expected = Taxonomy::CATALOG.flat_map { |feature_id, actions| actions.map { |a| [feature_id, a] } }
      assert_equal expected.sort, pairs.sort
    end

    # VEK-585 keys integration events with a deterministic UUIDv5 so vanalytics dedupes redeliveries.
    # A v5 id is still a UUID as far as z.string().uuid() is concerned, but nothing else asserts it.
    test 'a deterministic integration event_id still satisfies the schema' do
      EventEmitter.integration('github-integration', 'sync', provider: 'github', via: 'webhook',
                                                             key: %w[delivery-1 subscription-2],
                                                             properties: { webhook_event: 'pull_request.opened' })

      event = emitted.sole
      assert_match UUID, event['event_id']
      assert_equal Digest::UUID.uuid_v5(Taxonomy::EVENT_ID_NAMESPACE,
                                        'github:delivery-1:subscription-2:github-integration:sync'),
                   event['event_id']
      assert_schema_conformant(event)
    end

    test 'user_id is a bounded string when there is an actor' do
      Current.user = users(:one)

      EventEmitter.feature('issue-create', 'create')

      event = emitted.sole
      assert_equal users(:one).id.to_s, event['user_id']
      assert_schema_conformant(event)
    end

    # The webhook and job paths have no Current.user. The key must be absent, not present-and-null.
    test 'user_id is absent rather than null when there is no actor' do
      EventEmitter.feature('github-integration', 'sync', properties: { provider: 'github', via: 'webhook' })

      event = emitted.sole
      assert_not event.key?('user_id')
      assert_schema_conformant(event)
    end

    # 49 keys at the key-length cap plus one value at the value-length cap: 50 keys exactly.
    def maximal_properties
      (1...SCHEMA_MAX_PROPERTY_KEYS).to_h { |n| [format('k%063d', n), n] }
                                    .merge('v' * SCHEMA_MAX_PROPERTY_KEY => 's' * SCHEMA_MAX_PROPERTY_VALUE)
    end

    test 'an event at every schema boundary is still accepted' do
      maximal = {
        'event_id' => SecureRandom.uuid,
        'event_type' => 'feature.used',
        'feature_id' => 'f' * SCHEMA_MAX_STRING,
        'customer_id' => 'c' * SCHEMA_MAX_STRING,
        'user_id' => 'u' * SCHEMA_MAX_STRING,
        'action' => 'a' * SCHEMA_MAX_STRING,
        'properties' => maximal_properties,
        'timestamp' => 1.hour.ago.getlocal('+05:30').iso8601
      }

      assert_equal SCHEMA_MAX_PROPERTY_KEYS, maximal['properties'].size
      assert_schema_conformant(maximal, 'maximal')
    end

    # --- negative controls ----------------------------------------------------------------------
    #
    # Without these the whole file could pass vacuously: an assertion helper that checks nothing
    # conforms to everything. Each case breaches exactly one rule.

    def valid_event(overrides = {})
      {
        'event_id' => SecureRandom.uuid,
        'event_type' => 'feature.used',
        'feature_id' => 'issue-create',
        'customer_id' => 'mtasks-test',
        'action' => 'create',
        'properties' => { 'source' => 'server' },
        'timestamp' => Time.current.utc.iso8601
      }.merge(overrides)
    end

    def assert_rejected(overrides, message)
      error = assert_raises(Minitest::Assertion) { assert_schema_conformant(valid_event(overrides), 'control') }
      assert_match(/#{Regexp.escape(message)}/, error.message)
    end

    test 'the helper rejects an event_id that is not a UUID' do
      assert_rejected({ 'event_id' => 'evt_00000001' }, 'event_id is not a UUID')
    end

    test 'the helper rejects an event_type outside the enum' do
      assert_rejected({ 'event_type' => 'feature.abandoned' }, 'unknown event_type')
    end

    test 'the helper rejects a feature event with no feature_id' do
      assert_rejected({ 'feature_id' => '' }, 'feature_id is required')
    end

    test 'the helper rejects a blank customer_id' do
      assert_rejected({ 'customer_id' => '' }, 'customer_id is blank')
    end

    test 'the helper rejects a nested property value' do
      assert_rejected({ 'properties' => { 'shape' => { 'priority' => 'high' } } }, 'not a flat scalar')
    end

    test 'the helper rejects an array property value' do
      assert_rejected({ 'properties' => { 'lanes' => [1, 2] } }, 'not a flat scalar')
    end

    test 'the helper rejects a property key over 64 characters' do
      assert_rejected({ 'properties' => { 'k' * 65 => 1 } }, 'property key')
    end

    test 'the helper rejects a string property value over 1024 characters' do
      assert_rejected({ 'properties' => { 'entity' => 'x' * 1025 } }, 'too long')
    end

    test 'the helper rejects more than 50 property keys' do
      assert_rejected({ 'properties' => (1..51).to_h { |n| ["key_#{n}", n] } }, 'over 50 keys')
    end

    test 'the helper rejects a timestamp with no offset' do
      assert_rejected({ 'timestamp' => Time.current.strftime('%Y-%m-%dT%H:%M:%S') }, 'carries no offset')
    end

    test 'the helper rejects a timestamp past the ingest window' do
      assert_rejected({ 'timestamp' => 8.days.ago.utc.iso8601 }, 'outside the ingest window')
    end

    test 'the helper rejects a timestamp too far in the future' do
      assert_rejected({ 'timestamp' => 2.hours.from_now.utc.iso8601 }, 'too far in the future')
    end

    test 'the helper rejects an explicit null' do
      assert_rejected({ 'user_id' => nil }, 'explicit null')
    end

    test 'the helper rejects a field the schema would silently strip' do
      assert_rejected({ 'organization_id' => 'org_1' }, 'stripped in transit')
    end

    # --- drift guards ---------------------------------------------------------------------------
    #
    # Vektis::Taxonomy is the second Ruby transcription of the same Zod schema — the one the emitter
    # enforces at runtime. These compare the two so a change to either side surfaces here.

    test 'Taxonomy still matches the schema it transcribes' do
      assert_equal SCHEMA_EVENT_TYPES.sort, Taxonomy::EVENT_TYPES.sort
      assert_equal SCHEMA_FEATURE_TYPES.sort, Taxonomy::FEATURE_TYPES.sort
      assert_equal SCHEMA_MAX_STRING, Taxonomy::MAX_FIELD_LENGTH
      assert_equal SCHEMA_MAX_PROPERTY_KEYS, Taxonomy::MAX_PROPERTY_KEYS
      assert_equal SCHEMA_MAX_PROPERTY_KEY, Taxonomy::MAX_PROPERTY_KEY_LENGTH
      assert_equal SCHEMA_MAX_PROPERTY_VALUE, Taxonomy::MAX_STRING_VALUE_LENGTH
    end

    # Divergence (1) from the header: mtasks caps the whole event in bytes where Zod caps properties
    # alone in string length. Stricter is safe; the assertion is here so a future relaxation is a
    # deliberate edit rather than an accident.
    test 'the mtasks event cap is no looser than the schema property cap' do
      assert_operator Taxonomy::MAX_EVENT_BYTES, :<=, SCHEMA_MAX_PROPERTIES_JSON
    end

    test 'the client batches inside the limits the schema and the server enforce' do
      assert_equal SCHEMA_MAX_BATCH, ApiClient::MAX_BATCH_SIZE
      assert_operator ApiClient::MAX_BATCH_BYTES, :<, SCHEMA_MAX_BODY_BYTES
    end
  end
end
