require 'test_helper'

module Webhooks
  class HourglassControllerTest < ActionDispatch::IntegrationTest
    SECRET = 'whsec_test_1234567890abcdef'.freeze

    setup do
      @user = User.create!(name: 'Hook User',
                           email: "hook_#{SecureRandom.hex(4)}@example.com",
                           password: 'password')
      @workspace = Workspace.create!(name: 'Hook WS', owner: @user)
      @integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: "srv_#{SecureRandom.hex(4)}",
        hourglass_server_name: 'Acme',
        base_url: 'https://hg.test',
        webhook_secret: SECRET,
        active: true
      )
    end

    def sign(body, secret = SECRET)
      "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, body)}"
    end

    def post_webhook(body:, signature:, delivery_id: nil, event_type: 'message.created', timestamp: nil)
      headers = {
        'Content-Type' => 'application/json',
        'X-Hourglass-Event' => event_type,
        'X-Hourglass-Delivery' => delivery_id || "del_#{SecureRandom.hex(8)}",
        'X-Hourglass-Signature-256' => signature
      }
      headers['X-Hourglass-Timestamp'] = timestamp.to_s if timestamp

      post webhooks_hourglass_path(workspace_id: @workspace.id),
           params: body, headers: headers
    end

    test 'verified happy path persists delivery and enqueues processor job' do
      body = { 'version' => 1, 'message_id' => 'm1', 'body' => 'hi' }.to_json
      delivery_id = 'del_happy_1'

      assert_enqueued_with(job: HourglassWebhookProcessorJob) do
        assert_difference -> { WebhookDelivery.count }, 1 do
          post_webhook(body: body, signature: sign(body), delivery_id: delivery_id,
                       event_type: 'message.created')
        end
      end

      assert_response :ok
      delivery = WebhookDelivery.find_by(source: 'hourglass', delivery_id: delivery_id)
      assert_not_nil delivery
      assert_equal 'message.created', delivery.event_type
      assert_equal 'm1', delivery.payload['message_id']
      @integration.reload
      assert_not_nil @integration.last_webhook_at
    end

    test 'invalid signature returns 401 and does not persist' do
      body = '{"x":1}'

      assert_no_difference -> { WebhookDelivery.count } do
        post_webhook(body: body, signature: 'sha256=deadbeef', delivery_id: 'del_bad_sig')
      end

      assert_response :unauthorized
    end

    test 'missing signature returns 401' do
      body = '{}'
      headers = {
        'Content-Type' => 'application/json',
        'X-Hourglass-Event' => 'message.created',
        'X-Hourglass-Delivery' => 'del_no_sig'
      }

      assert_no_difference -> { WebhookDelivery.count } do
        post webhooks_hourglass_path(workspace_id: @workspace.id),
             params: body, headers: headers
      end

      assert_response :unauthorized
    end

    test 'replay outside window returns 401' do
      body = '{"x":1}'
      old_timestamp = (Time.current.to_i - (10 * 60))

      assert_no_difference -> { WebhookDelivery.count } do
        post_webhook(body: body, signature: sign(body), delivery_id: 'del_old',
                     timestamp: old_timestamp)
      end

      assert_response :unauthorized
    end

    test 'within replay window succeeds' do
      body = '{"x":1}'
      ts = Time.current.to_i

      post_webhook(body: body, signature: sign(body), delivery_id: 'del_ts_ok',
                   timestamp: ts)

      assert_response :ok
    end

    test 'idempotent on delivery_id: second post is no-op' do
      body = '{"x":1}'
      delivery_id = 'del_dup_1'

      assert_difference -> { WebhookDelivery.count }, 1 do
        post_webhook(body: body, signature: sign(body), delivery_id: delivery_id)
      end
      assert_response :ok

      assert_no_difference -> { WebhookDelivery.count } do
        post_webhook(body: body, signature: sign(body), delivery_id: delivery_id)
      end
      assert_response :ok
    end

    test 'unknown integration returns 404' do
      body = '{}'
      headers = {
        'Content-Type' => 'application/json',
        'X-Hourglass-Event' => 'message.created',
        'X-Hourglass-Delivery' => 'del_no_int',
        'X-Hourglass-Signature-256' => sign(body)
      }

      post webhooks_hourglass_path(workspace_id: 999_999), params: body, headers: headers
      assert_response :not_found
    end

    test 'inactive integration returns 404' do
      @integration.update!(active: false)
      body = '{}'
      post_webhook(body: body, signature: sign(body), delivery_id: 'del_inactive')

      assert_response :not_found
    end

    test 'missing event header returns 400' do
      body = '{}'
      headers = {
        'Content-Type' => 'application/json',
        'X-Hourglass-Delivery' => 'del_no_event',
        'X-Hourglass-Signature-256' => sign(body)
      }

      post webhooks_hourglass_path(workspace_id: @workspace.id),
           params: body, headers: headers
      assert_response :bad_request
    end
  end
end
