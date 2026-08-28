require 'test_helper'
require 'webmock/minitest'

class VektisEventJobTest < ActiveJob::TestCase
  include VektisEventTestHelper

  ENDPOINT = 'http://vektis.test/api/v1/events'.freeze
  VEKTIS_VARS = %w[VEKTIS_ENABLED VEKTIS_ENDPOINT VEKTIS_SERVER_KEY].freeze

  setup do
    WebMock.disable_net_connect!
    @original_env = VEKTIS_VARS.index_with { |key| ENV.fetch(key, nil) }
    ENV['VEKTIS_ENABLED'] = 'true'
    ENV['VEKTIS_ENDPOINT'] = ENDPOINT
    ENV['VEKTIS_SERVER_KEY'] = 'vk_dev_secret_never_log_me'
  end

  teardown do
    @original_env.each { |key, value| ENV[key] = value }
    WebMock.reset!
    WebMock.allow_net_connect!
  end

  # --- helpers ---------------------------------------------------------------------------------

  # Already-built events, exactly as Vektis::EventEmitter hands them over: string keys, event_id
  # and timestamp already stamped.
  def event(overrides = {})
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

  # Every event_id that actually went over the wire, once per request — identical retries collapse
  # into one signature in WebMock's registry, so the count has to be read back out.
  def sent_event_ids
    WebMock::RequestRegistry.instance.requested_signatures.hash.flat_map do |signature, count|
      ids = JSON.parse(signature.body)['events'].map { |sent| sent['event_id'] }
      ids * count
    end
  end

  def retried_events
    ActiveJob::Arguments.deserialize(enqueued_jobs.sole[:args])
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

  # ActiveJob's log subscriber writes to ActiveJob::Base.logger, which is a separate reference from
  # Rails.logger — swapping only the latter captures the emitter's own lines but none of the
  # "Enqueued/Performing … with arguments" ones this is here to assert about.
  def capture_active_job_logs
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    original_job = ActiveJob::Base.logger
    original_rails = Rails.logger
    ActiveJob::Base.logger = logger
    Rails.logger = logger
    yield
    io.string
  ensure
    ActiveJob::Base.logger = original_job
    Rails.logger = original_rails
  end

  # --- delivery --------------------------------------------------------------------------------

  test 'posts the event it was handed' do
    stub_request(:post, ENDPOINT).to_return(status: 202, body: { accepted: 1 }.to_json)
    payload = event

    VektisEventJob.perform_now(payload)

    assert_equal [payload['event_id']], sent_event_ids
    assert_no_enqueued_jobs
  end

  test 'runs on its own queue' do
    assert_equal 'vektis', VektisEventJob.new.queue_name
  end

  # VEK-587: the sole argument is the finished event, so ActiveJob's default argument logging would
  # put user_id and every property value into stdout at info level on both enqueue and perform.
  test 'never logs its arguments, which are the event itself' do
    assert_not VektisEventJob.log_arguments?
  end

  test 'the suppression is scoped to this job and does not blind the rest of the app' do
    assert ApplicationJob.log_arguments?,
           'log_arguments must not be turned off globally — other jobs need their arguments logged'
  end

  test 'no property value reaches the log when the job is enqueued or performed' do
    stub_request(:post, ENDPOINT).to_return(status: 202, body: { accepted: 1 }.to_json)
    payload = event.merge('user_id' => '4217', 'properties' => { 'source' => 'server', 'count' => 99 })

    logs = capture_active_job_logs do
      VektisEventJob.perform_later(payload)
      perform_enqueued_jobs
    end

    assert_match(/VektisEventJob/, logs, 'guard: the subscriber has to be logging at all for this to mean anything')
    assert_no_match(/4217/, logs)
    assert_no_match(/count/, logs)
  end

  test 'no-ops without touching the network when analytics is disabled' do
    ENV['VEKTIS_ENABLED'] = 'false'

    VektisEventJob.perform_now(event)

    assert_not_requested :post, ENDPOINT
  end

  # --- idempotency across retries --------------------------------------------------------------

  # The load-bearing assertion of VEK-583. vanalytics dedupes on (organization_id, event_id), so a
  # regenerated UUID produces a duplicate row on every redelivery and nothing else would catch it.
  test 'sends the same event_id on every retry attempt' do
    stub_request(:post, ENDPOINT).to_return({ status: 500 }, { status: 202, body: { accepted: 1 }.to_json })
    payload = event

    VektisEventJob.perform_now(payload)
    assert_equal payload['event_id'], retried_events.sole['event_id']

    perform_enqueued_jobs
    assert_equal [payload['event_id'], payload['event_id']], sent_event_ids
  end

  test 'carries the original timestamp through a retry rather than re-stamping it' do
    stub_request(:post, ENDPOINT).to_return(status: 503)
    payload = event('timestamp' => 2.days.ago.utc.iso8601)

    VektisEventJob.perform_now(payload)

    assert_equal payload['timestamp'], retried_events.sole['timestamp']
  end

  # --- retry policy ----------------------------------------------------------------------------

  test 'honors Retry-After on a 429' do
    stub_request(:post, ENDPOINT).to_return(status: 429, headers: { 'Retry-After' => '30' },
                                            body: { retryAfter: 30 }.to_json)

    VektisEventJob.perform_now(event)

    assert_in_delta 30, enqueued_jobs.sole[:at] - Time.current.to_f, 2
  end

  test 'backs off exponentially on a server error' do
    stub_request(:post, ENDPOINT).to_return(status: 500)
    job = VektisEventJob.new(event)
    job.executions = 2 # third attempt: 5 * 2**2 = 20s, plus jitter

    job.perform_now

    assert_in_delta 22, enqueued_jobs.sole[:at] - Time.current.to_f, 3
  end

  test 'stops retrying after MAX_ATTEMPTS' do
    stub_request(:post, ENDPOINT).to_return(status: 500)
    job = VektisEventJob.new(event)
    job.executions = VektisEventJob::MAX_ATTEMPTS - 1

    logs = capture_logs { job.perform_now }

    assert_match(/dropped after #{VektisEventJob::MAX_ATTEMPTS} attempts/, logs)
    assert_no_enqueued_jobs
  end

  test 'still retries on the attempt before the ceiling' do
    stub_request(:post, ENDPOINT).to_return(status: 500)
    job = VektisEventJob.new(event)
    job.executions = VektisEventJob::MAX_ATTEMPTS - 2

    job.perform_now

    assert_equal 1, enqueued_jobs.size
  end

  # --- terminal rejections ---------------------------------------------------------------------

  test 'does not retry a validation failure' do
    stub_request(:post, ENDPOINT).to_return(status: 400, body: { errors: [{ path: 'feature_id' }] }.to_json)

    logs = capture_logs { VektisEventJob.perform_now(event) }

    assert_match(/no retry/, logs)
    assert_no_enqueued_jobs
  end

  test 'reports a rejected server key as its own operational fault' do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { message: 'invalid key' }.to_json)

    logs = capture_logs { VektisEventJob.perform_now(event) }

    assert_match(/rejected the server key/, logs)
    assert_no_enqueued_jobs
    assert_no_match(/vk_dev_secret_never_log_me/, logs)
  end

  # --- unexpected faults -------------------------------------------------------------------------

  # perform rescues RetryableError and nothing else, and ApplicationJob declares no retry_on, so an
  # unexpected fault has to fail once rather than re-enqueue itself forever. A stray `rescue
  # StandardError => e; retry_job` would loop to the queue's own limit instead of this job's.
  def with_broken_client(error, &)
    broken = Object.new
    broken.define_singleton_method(:post_events) { |*| raise error }
    with_stubbed_class_method(Vektis::ApiClient, :new, ->(*) { broken }, &)
  end

  test 'an unexpected ApiClient fault fails the job instead of retrying forever' do
    with_broken_client(ArgumentError.new('bad batch')) do
      assert_raises(ArgumentError) { VektisEventJob.perform_now(event) }
    end

    assert_no_enqueued_jobs
  end

  test 'a retryable fault raised straight from the client is still retried' do
    with_broken_client(Vektis::ApiClient::RetryableError.new('ingest down')) do
      VektisEventJob.perform_now(event)
    end

    assert_equal 1, enqueued_jobs.size
  end

  # --- staleness -------------------------------------------------------------------------------

  test 'drops an event that aged past the ingest window instead of re-stamping it' do
    logs = capture_logs { VektisEventJob.perform_now(event('timestamp' => 8.days.ago.utc.iso8601)) }

    assert_match(/older than/, logs)
    assert_not_requested :post, ENDPOINT
    assert_no_enqueued_jobs
  end

  test 'drops an unparseable timestamp' do
    capture_logs { VektisEventJob.perform_now(event('timestamp' => 'yesterday')) }

    assert_not_requested :post, ENDPOINT
  end

  test 'delivers the fresh events in a batch and drops only the stale ones' do
    stub_request(:post, ENDPOINT).to_return(status: 202, body: { accepted: 1 }.to_json)
    fresh = event
    stale = event('timestamp' => 30.days.ago.utc.iso8601)

    capture_logs { VektisEventJob.perform_now(stale, fresh) }

    assert_equal [fresh['event_id']], sent_event_ids
  end
end
