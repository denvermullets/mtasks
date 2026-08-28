# Shared assertions for the VEKTIS server call sites (VEK-584, VEK-585).
#
# Events are read back off the ActiveJob queue rather than off the wire: Vektis::EventEmitter
# builds and validates the event, then hands VektisEventJob the finished hash, so what is queued
# is literally what would be sent. Nothing here starts an HTTP request.
module VektisEventTestHelper
  VEKTIS_ENV_VARS = %w[VEKTIS_ENABLED VEKTIS_CUSTOMER_ID].freeze

  # Analytics is off by default and a developer's .env may switch it on, so tests that care set
  # the flag explicitly rather than inheriting whichever way the machine is configured.
  def enable_vektis!
    @original_vektis_env = VEKTIS_ENV_VARS.index_with { |key| ENV.fetch(key, nil) }
    ENV['VEKTIS_ENABLED'] = 'true'
    ENV['VEKTIS_CUSTOMER_ID'] = 'mtasks-test'
  end

  def restore_vektis_env!
    @original_vektis_env&.each { |key, value| ENV[key] = value }
  end

  # minitest 6 dropped minitest/mock and this app carries no mocking gem, so fault injection is
  # done by hand: define the class method, run the block, remove the override to reveal the real
  # one again.
  def with_stubbed_class_method(klass, name, replacement)
    klass.define_singleton_method(name) { |*args, **kwargs| replacement.call(*args, **kwargs) }
    yield
  ensure
    klass.singleton_class.send(:remove_method, name)
  end

  def emitted
    enqueued_jobs.select { |job| job[:job] == VektisEventJob }
                 .map { |job| ActiveJob::Arguments.deserialize(job[:args]).first }
  end

  def pairs
    emitted.map { |event| [event['feature_id'], event['action']] }
  end

  def assert_emitted(feature_id, action, message = nil)
    assert_includes pairs, [feature_id, action], message || "expected #{feature_id}/#{action} in #{pairs.inspect}"
  end

  def refute_emitted(feature_id, action)
    assert_not_includes pairs, [feature_id, action]
  end

  def event_for(feature_id, action = nil)
    emitted.detect do |event|
      event['feature_id'] == feature_id && (action.nil? || event['action'] == action)
    end
  end

  def events_for(feature_id, action = nil)
    emitted.select do |event|
      event['feature_id'] == feature_id && (action.nil? || event['action'] == action)
    end
  end

  # The taxonomy contract every server event must satisfy, regardless of where it was emitted:
  # a catalogued (feature_id, action) pair, property keys from the closed registry, and scalar
  # values only — a nil would 400 the whole batch it travels in.
  def assert_taxonomy_conformant(event)
    actions = Vektis::Taxonomy::CATALOG[event['feature_id']]
    assert_not_nil actions, "#{event['feature_id']} is not a server-owned feature_id"
    assert_includes actions, event['action']
    assert_empty event['properties'].keys - Vektis::Taxonomy::PROPERTY_KEYS
    event['properties'].each_value { |value| assert scalar?(value), "#{value.inspect} is not a scalar" }
    assert_equal 'server', event['properties']['source']
  end

  # properties is Record<string, string | number | boolean> — a single nil 400s the whole batch it
  # travels in, and a 400 is a drop with no retry.
  def scalar?(value)
    value.is_a?(String) || value.is_a?(Numeric) || [true, false].include?(value)
  end

  # §6: if a user typed it, it does not ship. Asserted against the values actually flowing through
  # each test rather than a fixed list, so a new leak fails the test that introduced it.
  #
  # Pass user-authored *text* only. This is a substring check, so a short value — an autoincrement
  # id, a one-word name — matches legitimate property values like "count":1 and fails for no reason.
  def assert_no_user_content(*forbidden)
    serialized = emitted.map { |event| JSON.generate(event['properties']) }.join(' ')
    forbidden.compact.each do |value|
      assert_not_includes serialized, value.to_s, "#{value.inspect} reached properties"
    end
  end
end
