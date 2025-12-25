module GithubWebhookVerification
  extend ActiveSupport::Concern

  private

  def verify_github_signature
    signature = request.headers['X-Hub-Signature-256']

    unless signature
      Rails.logger.warn('Missing GitHub webhook signature')
      head :unauthorized
      return
    end

    expected_signature = compute_signature(request.raw_post)

    return if Rack::Utils.secure_compare(signature, expected_signature)

    Rails.logger.warn('Invalid GitHub webhook signature')
    head :unauthorized
    nil
  end

  def compute_signature(payload_body)
    secret = ENV.fetch('GITHUB_WEBHOOK_SECRET', nil)
    "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, payload_body)}"
  end

  def webhook_payload
    @webhook_payload ||= JSON.parse(request.body.read)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse GitHub webhook payload: #{e.message}")
    {}
  end
end
