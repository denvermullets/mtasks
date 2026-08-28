require 'test_helper'
require 'webmock/minitest'

module Vektis
  class ApiClientTest < ActiveSupport::TestCase
    ENDPOINT = 'http://vektis.test/api/v1/events'.freeze
    SERVER_KEY = 'vk_dev_secret_never_log_me'.freeze
    PUBLISHABLE_KEY = 'vk_pub_browser_safe_wrong_key'.freeze
    VEKTIS_VARS = %w[VEKTIS_ENABLED VEKTIS_ENDPOINT VEKTIS_SERVER_KEY VEKTIS_PUBLISHABLE_KEY].freeze

    setup do
      WebMock.disable_net_connect!
      # Analytics is disabled by default, so every network case has to opt in explicitly.
      @original_env = VEKTIS_VARS.index_with { |key| ENV.fetch(key, nil) }
      ENV['VEKTIS_ENABLED'] = 'true'
      ENV['VEKTIS_ENDPOINT'] = ENDPOINT
      ENV['VEKTIS_SERVER_KEY'] = SERVER_KEY
      # Set to something distinguishable so a swapped key is a failure rather than a coincidence.
      ENV['VEKTIS_PUBLISHABLE_KEY'] = PUBLISHABLE_KEY
    end

    teardown do
      @original_env.each { |key, value| ENV[key] = value }
      WebMock.reset!
      WebMock.allow_net_connect!
    end

    # --- helpers ---------------------------------------------------------------------------

    def event(overrides = {})
      {
        event_id: SecureRandom.uuid,
        event_type: 'feature.used',
        feature_id: 'issue-create',
        customer_id: 'mtasks-local-dev',
        action: 'create',
        properties: { source: 'server' }
      }.merge(overrides)
    end

    def stub_accepted
      stub_request(:post, ENDPOINT).to_return do |req|
        { status: 202, body: { accepted: JSON.parse(req.body)['events'].size }.to_json }
      end
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

    # --- gating ----------------------------------------------------------------------------

    test 'no-ops without touching the network when analytics is disabled' do
      ENV['VEKTIS_ENABLED'] = 'false'

      result = ApiClient.new.post_events([event])

      assert result.ok?
      assert_equal :disabled, result.reason
      assert_equal 0, result.sent
      assert_not_requested :post, ENDPOINT
    end

    test 'no-ops on an empty batch' do
      result = ApiClient.new.post_events([])

      assert result.ok?
      assert_equal :empty, result.reason
      assert_not_requested :post, ENDPOINT
    end

    # --- success ---------------------------------------------------------------------------

    test 'posts the mandatory events wrapper with the documented headers' do
      stub_accepted

      result = ApiClient.new.post_events([event])

      assert result.ok?
      assert_equal :accepted, result.reason
      assert_equal 1, result.accepted
      assert_equal 1, result.sent
      assert_equal 0, result.dropped
      assert_requested(:post, ENDPOINT) do |req|
        body = JSON.parse(req.body)

        body.keys == ['events'] &&
          body['events'].size == 1 &&
          body['events'].first['event_type'] == 'feature.used' &&
          req.headers['Content-Type'] == 'application/json' &&
          req.headers['Accept'] == 'application/json' &&
          req.headers['X-Vektis-Key'] == SERVER_KEY &&
          req.headers['X-Vektis-Sdk'] == "mtasks-rails/#{ApiClient::VERSION}"
      end
    end

    test 'accepted reflects the server count, not the events sent' do
      stub_request(:post, ENDPOINT).to_return(status: 202, body: '{"accepted":0}')

      result = ApiClient.new.post_events([event])

      assert result.ok?
      assert_equal 0, result.accepted
      assert_equal 1, result.sent
    end

    # --- terminal statuses -----------------------------------------------------------------

    test '400 is terminal and the Zod issues reach the log' do
      body = { statusCode: 400, message: 'Validation failed',
               errors: [{ path: %w[events 0 feature_id], message: 'Required' }] }.to_json
      stub_request(:post, ENDPOINT).to_return(status: 400, body: body)

      result = nil
      logs = capture_logs { result = ApiClient.new.post_events([event]) }

      assert_not result.ok?
      assert_equal :validation_failed, result.reason
      assert_equal 1, result.dropped
      assert_includes logs, 'feature_id'
      assert_includes logs, 'no retry'
    end

    test '401 stops immediately instead of hammering the remaining batches' do
      stub_request(:post, ENDPOINT).to_return(status: 401, body: '{"statusCode":401}')

      result = nil
      capture_logs { result = ApiClient.new.post_events(Array.new(250) { event }) }

      assert_not result.ok?
      assert_equal :unauthorized, result.reason
      assert_equal 0, result.sent
      assert_equal 250, result.dropped
      assert_requested :post, ENDPOINT, times: 1
    end

    test '413 is terminal and not retried' do
      stub_request(:post, ENDPOINT).to_return(status: 413, body: '{"statusCode":413}')

      result = nil
      capture_logs { result = ApiClient.new.post_events([event]) }

      assert_not result.ok?
      assert_equal :payload_too_large, result.reason
    end

    test '415 is terminal and not retried' do
      stub_request(:post, ENDPOINT).to_return(status: 415, body: '{"statusCode":415}')

      result = nil
      capture_logs { result = ApiClient.new.post_events([event]) }

      assert_not result.ok?
      assert_equal :unsupported_media_type, result.reason
    end

    test 'an unmapped 4xx is terminal rather than retried' do
      stub_request(:post, ENDPOINT).to_return(status: 404, body: 'not found')

      result = nil
      capture_logs { result = ApiClient.new.post_events([event]) }

      assert_not result.ok?
      assert_equal :unexpected, result.reason
    end

    # --- retryable -------------------------------------------------------------------------

    test '429 raises with retry_after taken from the header when present' do
      stub_request(:post, ENDPOINT)
        .to_return(status: 429, headers: { 'Retry-After' => '12' }, body: '{"retryAfter":30}')

      error = assert_raises(ApiClient::RetryableError) { ApiClient.new.post_events([event]) }

      assert_equal 12, error.retry_after
    end

    test '429 falls back to the body retryAfter, which is all vanalytics actually sends' do
      stub_request(:post, ENDPOINT).to_return(status: 429, body: '{"retryAfter":30}')

      error = assert_raises(ApiClient::RetryableError) { ApiClient.new.post_events([event]) }

      assert_equal 30, error.retry_after
    end

    test '429 caps retry_after at 60 seconds' do
      stub_request(:post, ENDPOINT).to_return(status: 429, body: '{"retryAfter":9999}')

      error = assert_raises(ApiClient::RetryableError) { ApiClient.new.post_events([event]) }

      assert_equal 60, error.retry_after
    end

    test '429 with no hint at all defaults to 60 seconds' do
      stub_request(:post, ENDPOINT).to_return(status: 429, body: '')

      error = assert_raises(ApiClient::RetryableError) { ApiClient.new.post_events([event]) }

      assert_equal 60, error.retry_after
    end

    test '5xx raises RetryableError' do
      stub_request(:post, ENDPOINT).to_return(status: 503, body: '{"statusCode":503}')

      error = assert_raises(ApiClient::RetryableError) { ApiClient.new.post_events([event]) }

      assert_nil error.retry_after
    end

    test 'a refused connection raises RetryableError' do
      stub_request(:post, ENDPOINT).to_raise(Errno::ECONNREFUSED)

      assert_raises(ApiClient::RetryableError) { ApiClient.new.post_events([event]) }
    end

    test 'a read timeout raises RetryableError' do
      stub_request(:post, ENDPOINT).to_timeout

      assert_raises(ApiClient::RetryableError) { ApiClient.new.post_events([event]) }
    end

    # --- batching --------------------------------------------------------------------------

    test 'splits past the 100-event schema cap and aggregates the accepted counts' do
      stub_accepted

      result = ApiClient.new.post_events(Array.new(250) { event })

      assert result.ok?
      assert_equal 250, result.accepted
      assert_equal 250, result.sent
      assert_requested :post, ENDPOINT, times: 3
      assert_requested(:post, ENDPOINT, times: 3) { |req| JSON.parse(req.body)['events'].size <= 100 }
    end

    test 'splits on body size before the 512 KB server cap' do
      stub_accepted
      fat = event(properties: { source: 'server', blob: 'x' * 100_000 })

      result = ApiClient.new.post_events(Array.new(10) { fat })

      assert result.ok?
      assert_equal 10, result.sent
      assert_requested :post, ENDPOINT, times: 3
      assert_requested(:post, ENDPOINT, times: 3) { |req| req.body.bytesize < 512 * 1024 }
    end

    test 'an event too large to fit alone is dropped without wedging the rest of the batch' do
      stub_accepted
      oversized = event(properties: { source: 'server', blob: 'x' * 500_000 })

      result = nil
      logs = capture_logs { result = ApiClient.new.post_events([oversized, event]) }

      assert_not result.ok?
      assert_equal :event_too_large, result.reason
      assert_equal 1, result.dropped
      assert_equal 1, result.sent
      assert_equal 1, result.accepted
      assert_includes logs, 'larger than'
      assert_requested(:post, ENDPOINT, times: 1) { |req| JSON.parse(req.body)['events'].size == 1 }
    end

    # --- secrets ---------------------------------------------------------------------------

    # vanalytics accepts the key three ways — the X-Vektis-Key header, a `key` field in the body,
    # and a ?key= query param. The publishable key is the browser's, rate limited an order of
    # magnitude lower, and it is the one thing on this path that is safe to render into HTML. It
    # must never leave the server on an ingest request, by any of the three routes.
    test 'authenticates with the server key and never leaks the publishable one' do
      stub_accepted

      ApiClient.new.post_events([event])

      assert_requested(:post, ENDPOINT) do |req|
        req.headers['X-Vektis-Key'] == SERVER_KEY &&
          req.headers.values.none? { |value| value.to_s.include?(PUBLISHABLE_KEY) } &&
          !req.body.include?(PUBLISHABLE_KEY) &&
          !req.uri.to_s.include?(PUBLISHABLE_KEY)
      end
    end

    test 'sends the key in the header only, never in the body or the query string' do
      stub_accepted

      ApiClient.new.post_events([event])

      assert_requested(:post, ENDPOINT) do |req|
        !JSON.parse(req.body).key?('key') && req.uri.query.nil?
      end
    end

    # A missing Content-Type is a 415, which is a drop with no retry — so it has to hold on every
    # request the client makes, not just the first one.
    test 'sends application/json on every request in a split batch' do
      stub_accepted

      ApiClient.new.post_events(Array.new(250) { event })

      assert_requested(:post, ENDPOINT, times: 3) do |req|
        req.headers['Content-Type'] == 'application/json' && req.headers['X-Vektis-Key'] == SERVER_KEY
      end
    end

    test 'never writes the raw server key to the log' do
      stub_request(:post, ENDPOINT)
        .to_return(status: 400, body: { statusCode: 400, message: 'Validation failed' }.to_json)

      logs = capture_logs { ApiClient.new.post_events([event]) }

      assert_not_equal '', logs
      assert_not_includes logs, SERVER_KEY
    end
  end
end
