require 'net/http'
require 'uri'

module HourglassIntegrations
  class TestWebhookService < Service
    Result = Struct.new(:success?, :delivery_id, :error, keyword_init: true)

    def initialize(integration:, event_type:, body:, host:, protocol:)
      @integration = integration
      @event_type = event_type
      @body = body
      @host = host
      @protocol = protocol
    end

    def call
      delivery_id = "test-#{SecureRandom.hex(8)}"
      uri = URI.parse(webhook_url)
      req = build_request(uri, delivery_id)
      res = Net::HTTP.start(uri.hostname, uri.port,
                            use_ssl: uri.scheme == 'https',
                            open_timeout: 5, read_timeout: 5) { |http| http.request(req) }

      if (200..299).cover?(res.code.to_i)
        Result.new(success?: true, delivery_id: delivery_id, error: nil)
      else
        Result.new(success?: false, delivery_id: delivery_id, error: "HTTP #{res.code}")
      end
    rescue StandardError => e
      Result.new(success?: false, delivery_id: nil, error: e.message)
    end

    private

    def webhook_url
      "#{@protocol}#{@host}/webhooks/hourglass/#{@integration.workspace_id}"
    end

    def build_request(uri, delivery_id)
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json'
      req['X-Hourglass-Event'] = @event_type
      req['X-Hourglass-Delivery'] = delivery_id
      req['X-Hourglass-Timestamp'] = Time.current.to_i.to_s
      req['X-Hourglass-Signature-256'] = sign(@body)
      req.body = @body
      req
    end

    def sign(payload)
      "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), @integration.webhook_secret.to_s, payload.to_s)}"
    end
  end
end
