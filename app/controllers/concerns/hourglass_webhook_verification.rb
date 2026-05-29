module HourglassWebhookVerification
  extend ActiveSupport::Concern

  REPLAY_WINDOW_SECONDS = 5 * 60

  private

  def verify_hourglass_signature
    @integration = HourglassIntegration.active.find_by(workspace_id: params[:workspace_id])
    return reject_hourglass(:not_found, "Unknown hourglass workspace #{params[:workspace_id]}") unless @integration
    return reject_hourglass(:unauthorized, 'Hourglass webhook outside replay window') unless valid_timestamp?

    signature = request.headers['X-Hourglass-Signature-256']
    return reject_hourglass(:unauthorized, 'Missing Hourglass webhook signature') unless signature

    expected = compute_hourglass_signature(@integration.webhook_secret, request.raw_post)
    return if Rack::Utils.secure_compare(signature, expected)

    reject_hourglass(:unauthorized, 'Invalid Hourglass webhook signature')
  end

  def reject_hourglass(status, message)
    Rails.logger.warn(message)
    head status
    nil
  end

  def compute_hourglass_signature(secret, payload_body)
    "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret.to_s, payload_body.to_s)}"
  end

  def valid_timestamp?
    timestamp = request.headers['X-Hourglass-Timestamp']
    return true if timestamp.blank?

    sent_at = Integer(timestamp, 10)
    (Time.current.to_i - sent_at).abs <= REPLAY_WINDOW_SECONDS
  rescue ArgumentError, TypeError
    false
  end

  def webhook_payload
    @webhook_payload ||= JSON.parse(request.raw_post)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse Hourglass webhook payload: #{e.message}")
    {}
  end
end
