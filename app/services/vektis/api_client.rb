require 'json'
require 'net/http'
require 'uri'

# Server-side ingest client for VEKTIS analytics (VEK-582).
#
# There is no server SDK to reach for: @vektis-io/tracker is browser-only by construction
# (visibilitychange, pagehide, sendBeacon). This is a hand-rolled client against the documented
# POST /api/v1/events contract — the same route the browser SDK uses, since vanalytics does no
# browser / user-agent / SDK gating.
#
# Scope is transport and nothing else. It takes fully-formed event hashes and puts them on the
# wire. Building events, stamping `source: "server"`, generating `event_id` / `timestamp`, and
# enqueueing all belong to Vektis::EventEmitter and VektisEventJob (VEK-583).
#
# Shaped after Hourglass::ApiClient: net/http directly (every outbound client in this repo does),
# a 5s timeout because this must never hold a web request, and its own error classes.
module Vektis
  class ApiClient
    class Error < StandardError; end

    # Raised only for conditions a retry can actually fix — 429, 5xx, and network faults.
    # Every other outcome comes back as a Result, so a malformed payload or a bad key can never
    # burn a job's retry budget. `retry_after` is seconds, or nil when the server gave no hint.
    class RetryableError < Error
      attr_reader :retry_after

      def initialize(message, retry_after: nil)
        super(message)
        @retry_after = retry_after
      end
    end

    # `accepted` is what vanalytics *enqueued*, not what it stored. Deduplication on
    # (organization_id, event_id) happens asynchronously in its worker, so a fully duplicate batch
    # returns accepted: N with zero new rows. Never read it as a write confirmation.
    #
    # `ok` is false whenever any event failed to land — a terminal server rejection or a local
    # drop — so callers have one boolean to branch on and `dropped` / `reason` for the detail.
    Result = Struct.new(:ok, :accepted, :sent, :dropped, :reason, keyword_init: true) do
      def ok?
        ok
      end
    end

    TIMEOUT = 5

    # This client's own version, not the app's — mtasks has no version constant. Bump it when the
    # wire behavior here changes. Taxonomy §10 fixes the format; vanalytics persists the header to
    # impact_events.sdk_version, so it has to read unmistakably as non-browser.
    VERSION = '1.0.0'.freeze
    SDK_HEADER = "mtasks-rails/#{VERSION}".freeze

    MAX_BATCH_SIZE = 100        # hard schema max (events-schema: z.array(...).min(1).max(100))
    MAX_BATCH_BYTES = 480_000   # the browser SDK's pre-split guard, under the server's 512 KB cap
    WRAPPER_BYTES = 13          # '{"events":[]}'

    RETRY_AFTER_CAP = 60

    # Terminal statuses. None of these are worth a retry: the payload, the key, or this client is
    # wrong, and sending the same bytes again would only repeat the rejection.
    TERMINAL_REASONS = {
      400 => :validation_failed,      # Zod rejected the batch; body carries the issues
      401 => :unauthorized,           # bad or missing key — stop, do not hammer
      413 => :payload_too_large,      # we split below the cap, so this means the splitter is wrong
      415 => :unsupported_media_type  # client bug: Content-Type is not application/json
    }.freeze

    # Returns a Result. Raises RetryableError for 429 / 5xx / network faults so the calling job
    # can lean on ActiveJob's retry_on.
    def post_events(events)
      return noop(:disabled) unless Vektis.enabled?

      events = Array(events)
      return noop(:empty) if events.empty?

      batches, oversized = split_batches(events)
      log_oversized(oversized)
      return finished(0, 0, oversized) if batches.empty?

      deliver(batches, oversized)
    end

    private

    def deliver(batches, oversized)
      accepted = 0
      sent = 0
      uri = URI.parse(Vektis.endpoint)

      start(uri) do |http|
        batches.each_with_index do |batch, index|
          reason, count = post_batch(http, uri, batch)
          return terminal(reason, accepted, sent, oversized + unsent(batches, index)) unless reason == :accepted

          accepted += count
          sent += batch.size
        end
      end

      finished(accepted, sent, oversized)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, IOError => e
      # Raising here throws away the knowledge that earlier batches already landed. That is safe
      # only because event_id is generated once at emit time (VEK-583) and vanalytics dedupes on
      # (organization_id, event_id) — a whole-array retry re-sends them as no-ops. If VEK-583 ever
      # regenerates a UUID on retry, this becomes a duplicate-row bug.
      raise RetryableError, "VEKTIS ingest connection failed: #{e.message}"
    end

    # A single connection, reused across every batch in the call.
    def start(uri, &)
      Net::HTTP.start(uri.hostname, uri.port,
                      use_ssl: uri.scheme == 'https',
                      open_timeout: TIMEOUT, read_timeout: TIMEOUT, &)
    end

    def post_batch(http, uri, batch)
      handle_response(http.request(build_request(uri, batch)))
    end

    def build_request(uri, batch)
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json' # required; anything else is a 415
      req['Accept'] = 'application/json'
      req['X-Vektis-Key'] = Vektis.server_key  # header only — never the ?key= query fallback
      req['X-Vektis-SDK'] = SDK_HEADER
      req.body = JSON.generate(events: batch)  # the wrapper is mandatory, even for one event
      req
    end

    def handle_response(res)
      code = res.code.to_i
      return [:accepted, accepted_count(res)] if code == 202
      raise RetryableError.new('VEKTIS ingest rate limited (429)', retry_after: retry_after(res)) if code == 429
      raise RetryableError, "VEKTIS ingest server error (#{code})" if code >= 500

      reason = TERMINAL_REASONS.fetch(code, :unexpected)
      log_terminal(reason, code, res)
      [reason, 0]
    end

    # vanalytics does not actually set a Retry-After header today — only `retryAfter` in the JSON
    # body (server/src/controllers/v1/events.controller.ts). The documented contract promises the
    # header, so read it first and fall back to the body. Capped at 60s, matching the browser SDK.
    def retry_after(res)
      seconds = res['Retry-After'].to_s.to_i
      seconds = parse_json(res.body)['retryAfter'].to_i unless seconds.positive?
      return RETRY_AFTER_CAP unless seconds.positive?

      [seconds, RETRY_AFTER_CAP].min
    end

    def accepted_count(res)
      parse_json(res.body)['accepted'].to_i
    end

    def parse_json(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # Two hard caps: 100 events per request, and a 512 KB body. We split at 480 KB so wrapper and
    # header overhead can never push a batch over. Anything that cannot fit alone is dropped
    # rather than allowed to wedge the batch — unreachable given the taxonomy's closed property
    # registry (largest defined event is well under 500 bytes), but cheap to guarantee.
    def split_batches(events)
      sized = events.map { |event| [event, JSON.generate(event).bytesize + 1] }
      oversized, fitting = sized.partition { |_event, size| size > MAX_BATCH_BYTES }
      [pack(fitting), oversized.size]
    end

    def pack(sized_events)
      batches = []
      current = []
      bytes = WRAPPER_BYTES

      sized_events.each do |event, size|
        if current.size >= MAX_BATCH_SIZE || bytes + size > MAX_BATCH_BYTES
          batches << current
          current = []
          bytes = WRAPPER_BYTES
        end
        current << event
        bytes += size
      end

      batches << current if current.any?
      batches
    end

    def unsent(batches, index)
      batches[index..].sum(&:size)
    end

    def noop(reason)
      Result.new(ok: true, accepted: 0, sent: 0, dropped: 0, reason: reason)
    end

    def finished(accepted, sent, dropped)
      Result.new(ok: dropped.zero?, accepted: accepted, sent: sent, dropped: dropped,
                 reason: dropped.zero? ? :accepted : :event_too_large)
    end

    def terminal(reason, accepted, sent, dropped)
      Result.new(ok: false, accepted: accepted, sent: sent, dropped: dropped, reason: reason)
    end

    # The error envelope is { statusCode, message, errors } and never echoes the API key — the key
    # travels in a header and is not reflected. Nothing here interpolates Vektis.server_key.
    def log_terminal(reason, code, res)
      Rails.logger.error(
        "Vektis::ApiClient dropped batch (#{code} #{reason}, no retry): #{res.body.to_s[0, 1000]}"
      )
    end

    def log_oversized(count)
      return if count.zero?

      Rails.logger.error(
        "Vektis::ApiClient dropped #{count} event(s) larger than #{MAX_BATCH_BYTES} bytes"
      )
    end
  end
end
