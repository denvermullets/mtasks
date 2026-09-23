require 'vektis/testing'

# Shared assertions for the VEKTIS server call sites (VEK-584, VEK-585).
#
# Reading events off the ActiveJob queue is Vektis::Testing's job. What stays here is mtasks' half:
# connecting a team, the short names the call-site tests were written against, and the taxonomy and
# user-content checks, which are stricter than the gem's.
module VektisEventTestHelper
  include Vektis::Testing

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

  # The tenant ids the batches would be delivered under, which for mtasks are team ids.
  def emitted_team_ids = vektis_tenant_ids

  def emitted = vektis_events

  def pairs = vektis_pairs

  def event_for(feature_id, action = nil) = vektis_event_for(feature_id, action)

  # The gem's assertion takes no default message; this one names what was emitted instead.
  def assert_emitted(feature_id, action, message = nil)
    assert_vektis_emitted(feature_id, action, message || "expected #{feature_id}/#{action} in #{pairs.inspect}")
  end

  def refute_emitted(feature_id, action)
    assert_not_includes pairs, [feature_id, action]
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
    actions = EventTaxonomy::CATALOG[event['feature_id']]
    assert_not_nil actions, "#{event['feature_id']} is not a server-owned feature_id"
    assert_includes actions, event['action']
    assert_empty event['properties'].keys - EventTaxonomy::PROPERTY_KEYS
    event['properties'].each_value { |value| assert scalar?(value), "#{value.inspect} is not a scalar" }
    assert_includes Vektis::Schema::SOURCES, event['properties']['source']
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
