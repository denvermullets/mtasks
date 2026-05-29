require 'cgi'
require 'json'
require 'net/http'
require 'uri'

class Hourglass::ApiClient
  class Error < StandardError; end
  class Unauthorized < Error; end
  class NotFound < Error; end

  TIMEOUT = 5

  attr_accessor :server_id

  def self.for_integration(integration)
    new(
      base_url: integration.base_url,
      api_token: integration.api_token,
      server_id: integration.hourglass_server_id
    )
  end

  def initialize(base_url:, api_token:, server_id: nil)
    @base_url = base_url
    @api_token = api_token
    @server_id = server_id
  end

  def verify_token
    get('/api/v1/me')
  end

  def discover_channels!
    raise Error, 'Hourglass server_id missing; call handshake! first' if server_id.blank?

    res = get("/api/v1/servers/#{server_id}/channels")
    list = res.is_a?(Hash) && res['channels'] ? res['channels'] : res
    Array(list)
  end

  def fetch_channel(channel_id)
    get("/api/v1/channels/#{channel_id}")
  end

  def list_channel_messages(channel_id, since: nil, limit: 50)
    query = { limit: limit }
    query[:since] = since if since
    get("/api/v1/channels/#{channel_id}/messages?#{URI.encode_www_form(query)}")
  end

  def post_channel_message(channel_id, body:, data: nil, message_type: nil, idempotency_key: nil)
    payload = build_message_payload(body: body, data: data, message_type: message_type)
    post("/api/v1/channels/#{channel_id}/messages", payload, idempotency_key: idempotency_key)
  end

  def post_thread_message(message_id, body:, data: nil, message_type: nil, idempotency_key: nil)
    payload = build_message_payload(body: body, data: data, message_type: message_type)
    post("/api/v1/messages/#{message_id}/replies", payload, idempotency_key: idempotency_key)
  end

  def fetch_message(id)
    get("/api/v1/messages/#{id}")
  end

  def pin_message(id)
    post("/api/v1/messages/#{id}/pin", {})
  end

  def unpin_message(id)
    post("/api/v1/messages/#{id}/unpin", {})
  end

  def edit_message(id, body:)
    patch("/api/v1/messages/#{id}", { body: body })
  end

  def identify_user(email:)
    get("/api/v1/users/lookup?email=#{CGI.escape(email.to_s)}")
  end

  private

  attr_reader :base_url, :api_token

  def build_message_payload(body:, data:, message_type:)
    merged_data = { source: 'mtasks' }.merge(data || {})
    payload = { body: body, data: merged_data }
    payload[:message_type] = message_type if message_type
    payload
  end

  def get(path)
    request(Net::HTTP::Get, path)
  end

  def post(path, payload, idempotency_key: nil)
    request(Net::HTTP::Post, path, payload, idempotency_key: idempotency_key)
  end

  def patch(path, payload, idempotency_key: nil)
    request(Net::HTTP::Patch, path, payload, idempotency_key: idempotency_key)
  end

  def request(klass, path, payload = nil, idempotency_key: nil)
    res = perform_request(klass, path, payload, idempotency_key: idempotency_key)
    handle_response(res, path)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise Error, "Hourglass connection failed: #{e.message}"
  end

  def perform_request(klass, path, payload, idempotency_key: nil)
    uri = URI.join(base_url.to_s, path)
    req = klass.new(uri)
    req['Authorization'] = "Bearer #{api_token}"
    req['Accept'] = 'application/json'
    req['Idempotency-Key'] = idempotency_key if idempotency_key
    if payload
      req['Content-Type'] = 'application/json'
      req.body = payload.to_json
    end
    Net::HTTP.start(uri.hostname, uri.port,
                    use_ssl: uri.scheme == 'https',
                    open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.request(req) }
  end

  def handle_response(res, path)
    case res.code.to_i
    when 200, 201
      res.body.to_s.empty? ? {} : JSON.parse(res.body)
    when 204
      {}
    when 401, 403
      raise Unauthorized, "Hourglass rejected token (#{res.code})"
    when 404
      raise NotFound, "Hourglass 404 for #{path}"
    else
      raise Error, "Hourglass #{res.code} for #{path}"
    end
  end
end
