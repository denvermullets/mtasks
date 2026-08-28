# Shared assertions for the VEKTIS server call sites (VEK-584, VEK-585).
#
# Events are read back off the ActiveJob queue rather than off the wire: Vektis::EventEmitter
# builds and validates the event, then hands VektisEventJob the finished hash, so what is queued
# is literally what would be sent. Nothing here starts an HTTP request.
module VektisEventTestHelper
  VEKTIS_TEST_CUSTOMER_ID = 'mtasks-test'.freeze

  # Analytics is per-team now, so "enabled" means a connected TeamVektisIntegration rather than an
  # ENV flag. Tests that assert on emission call this for the team they act as.
  def enable_vektis!(team, customer_id: VEKTIS_TEST_CUSTOMER_ID)
    TeamVektisIntegration.find_or_initialize_by(team: team).tap do |integration|
      integration.update!(
        enabled: true,
        publishable_key: 'vk_pub_test',
        server_key: 'vk_test_server',
        customer_id: customer_id
      )
    end
  end

  def disable_vektis!(team)
    TeamVektisIntegration.find_by(team: team)&.update!(enabled: false)
  end

  # The team_id VektisEventJob was enqueued with, which is the tenant the batch would be delivered
  # under. Separate from the event body, where the tenant appears as customer_id.
  def emitted_team_ids
    enqueued_jobs.select { |job| job[:job] == VektisEventJob }
                 .map { |job| ActiveJob::Arguments.deserialize(job[:args]).first }
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

  # VektisEventJob takes (team_id, *events), so the event bodies start at index 1.
  def emitted
    enqueued_jobs.select { |job| job[:job] == VektisEventJob }
                 .flat_map { |job| ActiveJob::Arguments.deserialize(job[:args]).drop(1) }
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
  #
  # `source` is a parameter because the v1 API is a catalogued surface too and stamps `api`; it is
  # still asserted rather than skipped, because it is the one field that separates the surfaces.
  def assert_taxonomy_conformant(event, source: 'server')
    actions = Vektis::Taxonomy::CATALOG[event['feature_id']]
    assert_not_nil actions, "#{event['feature_id']} is not a server-owned feature_id"
    assert_includes actions, event['action']
    assert_empty event['properties'].keys - Vektis::Taxonomy::PROPERTY_KEYS
    event['properties'].each_value { |value| assert scalar?(value), "#{value.inspect} is not a scalar" }
    assert_includes Vektis::Taxonomy::SOURCES, event['properties']['source']
    assert_equal source, event['properties']['source']
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
