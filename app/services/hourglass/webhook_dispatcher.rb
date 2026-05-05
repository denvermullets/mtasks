require 'net/http'
require 'openssl'
require 'securerandom'
require 'uri'

module Hourglass
  class WebhookDispatcher < Service
    Result = Struct.new(:status, :delivery_id, keyword_init: true)

    def initialize(integration:, event_type:, data:)
      @integration = integration
      @event_type = event_type
      @data = data
    end

    def call
      if @integration.hourglass_integration_id.blank?
        raise Hourglass::ApiClient::Error,
              'integration missing hourglass_integration_id'
      end

      delivery_id = SecureRandom.uuid
      body = build_body(delivery_id)
      response = send_request(body, delivery_id)
      handle_response(response, delivery_id)
    end

    private

    def build_body(delivery_id)
      JSON.generate(
        version: 1,
        event: @event_type,
        delivery_id: delivery_id,
        data: @data
      )
    end

    def send_request(body, delivery_id)
      uri = URI.join(@integration.base_url.to_s, "/webhooks/mtasks/#{@integration.hourglass_integration_id}")
      req = build_request(uri, body, delivery_id)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                          open_timeout: Hourglass::ApiClient::TIMEOUT,
                                          read_timeout: Hourglass::ApiClient::TIMEOUT) do |http|
        http.request(req)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise Hourglass::ApiClient::Error, "Hourglass connection failed: #{e.message}"
    end

    def build_request(uri, body, delivery_id)
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', @integration.webhook_secret.to_s, body)}"
      req = Net::HTTP::Post.new(uri)
      req['Content-Type']           = 'application/json'
      req['X-Mtasks-Event']         = @event_type
      req['X-Mtasks-Delivery']      = delivery_id
      req['X-Mtasks-Timestamp']     = Time.current.to_i.to_s
      req['X-Mtasks-Signature-256'] = signature
      req.body = body
      req
    end

    def handle_response(response, delivery_id)
      case response.code.to_i
      when 200, 201, 204 then Result.new(status: response.code.to_i, delivery_id: delivery_id)
      when 401, 403 then raise Hourglass::ApiClient::Unauthorized, "Hourglass rejected webhook (#{response.code})"
      when 404 then raise Hourglass::ApiClient::NotFound, 'Hourglass 404 on webhook delivery'
      else raise Hourglass::ApiClient::Error, "Hourglass #{response.code} on webhook delivery"
      end
    end
  end
end
