# Off-request delivery for the events Vektis::EventEmitter builds (VEK-583).
#
# The job is deliberately dumb: it does not build events, generate ids, or stamp timestamps. It
# receives finished event hashes and hands them to Vektis::ApiClient. That split is what makes
# redelivery safe — vanalytics dedupes on (organization_id, event_id), and the emitter generated
# that id once, so every retry of this job re-sends the same bytes and lands as a no-op.
#
# Retry classification lives in the client, not here. Vektis::ApiClient raises RetryableError only
# for 429 / 5xx / network faults; every terminal rejection (400, 401, 413, 415) comes back as a
# Result instead. That is why this job needs no discard_on: a malformed payload or a bad key can
# never reach the retry path, let alone burn a retry budget.
class VektisEventJob < ApplicationJob
  # Its own queue, not :default. config/queue.yml workers take `queues: "*"` so this needs no
  # config change, and it lets analytics work be inspected or purged on its own — the operational
  # half of VEK-587's kill switch.
  queue_as :vektis

  # The sole argument is a fully-built event, so ActiveJob's default argument logging would write
  # user_id and every property value to stdout at info level on both enqueue and perform (VEK-587).
  # Scoped to this job rather than set globally: config.active_job.log_arguments = false would blind
  # every other job in the app. The event is still persisted to solid_queue_jobs.arguments, which is
  # mtasks' own database holding the low-cardinality structural data the taxonomy already permits —
  # a different risk class from logs that ship off-box.
  self.log_arguments = false

  MAX_ATTEMPTS = 5
  BASE_BACKOFF = 5

  # Ingest rejects any timestamp older than 7 days with a 400. Stop a day inside that boundary so
  # a job cannot age out between the check here and the request going out.
  MAX_EVENT_AGE = 6.days

  def perform(*events)
    # Re-checked because the flag can flip between enqueue and run. The emitter's check is what
    # keeps the queue empty while off; this one keeps an already-queued event from delivering.
    return unless Vektis.enabled?

    fresh, stale = events.map { |event| event.to_h.stringify_keys }.partition { |event| fresh?(event) }
    log_stale(stale)
    return if fresh.empty?

    result = Vektis::ApiClient.new.post_events(fresh)
    log_result(result) unless result.ok?
  rescue Vektis::ApiClient::RetryableError => e
    requeue(e)
  end

  private

  # Re-stamping a stale event would file week-old activity under today's date and quietly corrupt
  # every time-series read of the data, which is worse than losing one very late analytics event.
  # Drop it. A blank or unparseable timestamp counts as stale — it would 400 anyway.
  def fresh?(event)
    timestamp = event['timestamp']
    return false if timestamp.blank?

    Time.iso8601(timestamp.to_s) > MAX_EVENT_AGE.ago
  rescue ArgumentError
    false
  end

  # retry_on cannot be used here: its `wait:` proc is called with `executions` only
  # (ActiveJob::Exceptions#determine_delay), so it has no way to read Retry-After off the error.
  def requeue(error)
    if executions >= MAX_ATTEMPTS
      Rails.logger.error("VektisEventJob dropped after #{executions} attempts: #{error.message}")
      return
    end

    retry_job(wait: error.retry_after || backoff, error: error)
  end

  # 5s, 10s, 20s, 40s plus jitter. Bounded on purpose — the queue must not fill with analytics
  # events that will never be deliverable. ApiClient already caps a server-supplied Retry-After.
  def backoff
    (BASE_BACKOFF * (2**(executions - 1))) + rand(BASE_BACKOFF)
  end

  def log_stale(stale)
    return if stale.empty?

    Rails.logger.error("VektisEventJob dropped #{stale.size} event(s) older than #{MAX_EVENT_AGE.inspect}")
  end

  # An unauthorized key is an operational fault rather than a data fault, so it gets its own line
  # in the log. Disabling on it is VEK-587's call, not this job's.
  def log_result(result)
    if result.reason == :unauthorized
      Rails.logger.error('VektisEventJob: VEKTIS rejected the server key (401) — analytics is not being recorded')
      return
    end

    Rails.logger.error("VektisEventJob: #{result.dropped} event(s) dropped (#{result.reason}), no retry")
  end
end
