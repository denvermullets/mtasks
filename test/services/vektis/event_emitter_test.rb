require 'test_helper'

module Vektis
  class EventEmitterTest < ActiveJob::TestCase
    CUSTOMER_ID = 'mtasks-test'.freeze

    setup do
      @user = User.create!(name: 'Emitter', email: "emit_#{SecureRandom.hex(4)}@example.com",
                           password: 'password')
      @workspace = Workspace.create!(name: 'Emit WS', owner: @user)
      @team = @workspace.teams.create!(name: 'Emit Team', identifier: 'EMT')
      connect!(@team)
    end

    # --- helpers -----------------------------------------------------------------------------

    # `validate: false` on purpose: one case writes a blank customer_id, which the model rejects.
    # That is exactly the row the emitter's own runtime guard exists to catch, so the test has to be
    # able to create it.
    def connect!(team, enabled: true, customer_id: CUSTOMER_ID)
      integration = TeamVektisIntegration.find_or_initialize_by(team: team)
      integration.assign_attributes(enabled: enabled, publishable_key: 'vk_pub_emit',
                                    server_key: 'vk_emit', customer_id: customer_id)
      integration.save!(validate: false)
      integration
    end

    # VektisEventJob takes (team_id, *events), so the event body is the second argument.
    def enqueued_event
      assert_equal 1, enqueued_jobs.size
      ActiveJob::Arguments.deserialize(enqueued_jobs.first[:args])[1]
    end

    def enqueued_team_id
      ActiveJob::Arguments.deserialize(enqueued_jobs.first[:args]).first
    end

    # The emitter raises in development and test on purpose; the production branch logs and drops
    # instead, so exercising it means standing outside Rails.env.local?.
    def as_production
      original = Rails.env
      Rails.env = 'production'
      yield
    ensure
      Rails.env = original
    end

    def capture_logs
      io = StringIO.new
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      yield
      io.string
    ensure
      Rails.logger = original
    end

    def with_broken_enqueue
      original = VektisEventJob.method(:perform_later)
      VektisEventJob.define_singleton_method(:perform_later) { |*| raise 'queue database is down' }
      yield
    ensure
      VektisEventJob.singleton_class.send(:remove_method, :perform_later)
      VektisEventJob.define_singleton_method(:perform_later, &original)
    end

    # --- the built event ---------------------------------------------------------------------

    test 'builds a complete event and enqueues it for delivery' do
      EventEmitter.feature('issue-create', 'create', properties: { via: 'web', surface: 'board' }, team: @team)

      event = enqueued_event
      assert_match(/\A[0-9a-f-]{36}\z/, event['event_id'])
      assert_equal 'feature.used', event['event_type']
      assert_equal 'issue-create', event['feature_id']
      assert_equal 'mtasks-test', event['customer_id']
      assert_equal 'create', event['action']
      assert_equal({ 'via' => 'web', 'surface' => 'board', 'source' => 'server' }, event['properties'])
    end

    test 'stamps an ISO 8601 timestamp with an offset at emit time' do
      freeze_time do
        EventEmitter.feature('issue-create', 'create', team: @team)

        assert_equal Time.current.utc.iso8601, enqueued_event['timestamp']
      end
    end

    # The webhook case from §4.5: no Current.user, and the schema's optional fields reject an
    # explicit null, so the key has to be absent rather than present-and-nil.
    test 'omits user_id entirely when there is no actor' do
      EventEmitter.feature('hourglass-integration', 'sync', team: @team,
                                                            properties: { provider: 'hourglass' })

      event = enqueued_event
      assert_nil Current.user
      assert_not event.key?('user_id')
      assert_empty(event.select { |_key, value| value.nil? })
    end

    test 'stamps source server and refuses to let a call site override it' do
      EventEmitter.feature('comment', 'create', properties: { source: 'browser', entity: 'issue' }, team: @team)

      assert_equal 'server', enqueued_event['properties']['source']
    end

    test 'preserves a caller-supplied event_id for deterministic webhook ids' do
      event_id = Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, 'github:42:sync')

      EventEmitter.feature('hourglass-integration', 'sync', team: @team,
                                                            properties: { provider: 'hourglass' }, event_id: event_id)

      assert_equal event_id, enqueued_event['event_id']
    end

    test 'takes user_id from Current.user as a string' do
      user = User.create!(name: 'Emit', email: 'emit@example.com', password: 'password')
      Current.user = user

      EventEmitter.feature('issue-create', 'create', team: @team)

      assert_equal user.id.to_s, enqueued_event['user_id']
    end

    test 'keeps only flat scalars in properties and stringifies symbols' do
      EventEmitter.feature('issue-workflow', 'move', team: @team,
                                                     properties: { via: :web, from_position: 1, to_position: 3,
                                                                   direction: 'forward', priority: nil,
                                                                   count: [1, 2], depth: { a: 1 } })

      assert_equal({ 'via' => 'web', 'from_position' => 1, 'to_position' => 3,
                     'direction' => 'forward', 'source' => 'server' },
                   enqueued_event['properties'])
    end

    # --- gating ------------------------------------------------------------------------------

    test 'enqueues nothing when analytics is disabled' do
      connect!(@team, enabled: false)

      assert_no_enqueued_jobs do
        EventEmitter.feature('issue-create', 'create', team: @team)
      end
    end

    test 'validates even while disabled so a bad call site still fails in CI' do
      connect!(@team, enabled: false)

      assert_raises(EventEmitter::InvalidEvent) do
        EventEmitter.feature(nil, 'create', team: @team)
      end
    end

    # --- structural validation ---------------------------------------------------------------

    test 'rejects a feature event with no feature_id' do
      error = assert_raises(EventEmitter::InvalidEvent) { EventEmitter.feature(nil, 'create', team: @team) }

      assert_match(/feature_id is required/, error.message)
      assert_no_enqueued_jobs
    end

    test 'rejects an unknown event_type' do
      assert_raises(EventEmitter::InvalidEvent) do
        EventEmitter.emit(event_type: 'feature.abandoned', feature_id: 'issue-create', team: @team)
      end
    end

    test 'rejects a blank customer_id as a deploy fault' do
      connect!(@team, customer_id: '')

      error = assert_raises(EventEmitter::InvalidEvent) { EventEmitter.feature('comment', 'create', team: @team) }

      assert_match(/customer_id is blank/, error.message)
    end

    test 'rejects properties over the key cap' do
      properties = (1..51).to_h { |n| ["key_#{n}", n] }

      assert_raises(EventEmitter::InvalidEvent) do
        EventEmitter.feature('issue-create', 'create', properties: properties, team: @team)
      end
    end

    test 'drops rather than raises on an invalid event outside development' do
      logs = as_production do
        capture_logs { assert_nil EventEmitter.feature(nil, 'create', team: @team) }
      end

      assert_match(/dropped invalid event/, logs)
      assert_no_enqueued_jobs
    end

    # --- taxonomy audit ----------------------------------------------------------------------

    test 'rejects a feature_id the server does not own' do
      error = assert_raises(EventEmitter::InvalidEvent) do
        EventEmitter.feature('issue-search', 'search', properties: { query_length: 4 }, team: @team)
      end

      assert_match(/not a server-owned feature_id/, error.message)
    end

    test 'rejects an action outside the feature catalog' do
      error = assert_raises(EventEmitter::InvalidEvent) do
        EventEmitter.feature('issue-create', 'complete', team: @team)
      end

      assert_match(/not a issue-create action/, error.message)
    end

    test 'rejects a property key outside the closed registry' do
      error = assert_raises(EventEmitter::InvalidEvent) do
        EventEmitter.feature('comment', 'create', properties: { issue_title: 'leaked' }, team: @team)
      end

      assert_match(/closed property registry/, error.message)
    end

    test 'still delivers on taxonomy drift outside development, with a warning' do
      logs = as_production do
        capture_logs { EventEmitter.feature('comment', 'create', team: @team, properties: { issue_id: 7 }) }
      end

      assert_match(/taxonomy drift/, logs)
      assert_equal 1, enqueued_jobs.size
    end

    # --- the PII backstop (VEK-587) ----------------------------------------------------------

    test 'strips an unregistered property key outside development rather than shipping it' do
      as_production do
        capture_logs { EventEmitter.feature('comment', 'create', team: @team, properties: { issue_title: 'leaked' }) }
      end

      properties = enqueued_event['properties']
      assert_not_includes properties.keys, 'issue_title',
                          'an unregistered key must never reach impact_events.properties'
      assert_equal 'server', properties['source'], 'the rest of the event still ships'
    end

    test 'strips only the unregistered keys and keeps the registered ones' do
      as_production do
        capture_logs do
          EventEmitter.feature('issue-label', 'apply', team: @team,
                                                       properties: { entity: 'issue', count: 2, label_name: 'Bug' })
        end
      end

      properties = enqueued_event['properties']
      assert_equal %w[count entity source], properties.keys.sort
      assert_equal 2, properties['count']
    end

    test 'names the dropped key in the warning so the call site can be found' do
      logs = as_production do
        capture_logs { EventEmitter.feature('comment', 'create', team: @team, properties: { comment_body: 'hi' }) }
      end

      assert_match(/comment_body/, logs)
      assert_match(/dropped/, logs)
    end

    test 'unknown feature_id and action still ship, since a slug carries no user content' do
      as_production do
        capture_logs { EventEmitter.feature('comment', 'undocumented-action', team: @team) }
      end

      assert_equal 'undocumented-action', enqueued_event['action'],
                   'catalog drift must not lose data — only property drift is a PII risk'
    end

    # --- fail-safety -------------------------------------------------------------------------

    test 'emits nothing for a write that rolled back' do
      assert_no_enqueued_jobs do
        ActiveRecord::Base.transaction do
          EventEmitter.feature('issue-create', 'create', team: @team)
          raise ActiveRecord::Rollback
        end
      end
    end

    test 'defers the enqueue until the surrounding transaction commits' do
      ActiveRecord::Base.transaction do
        EventEmitter.feature('issue-create', 'create', team: @team)
        assert_no_enqueued_jobs
      end

      assert_equal 1, enqueued_jobs.size
    end

    test 'swallows and logs an enqueue failure rather than raising into the caller' do
      logs = with_broken_enqueue do
        capture_logs { assert_nil EventEmitter.feature('issue-create', 'create', team: @team) }
      end

      assert_match(/failed to enqueue/, logs)
    end
  end
end
