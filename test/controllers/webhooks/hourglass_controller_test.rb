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

    def post_webhook(body:, signature:, delivery_id: nil, event_type: 'message.created', timestamp: nil,
                     path: webhooks_hourglass_path(public_id: @integration.public_id))
      headers = {
        'Content-Type' => 'application/json',
        'X-Hourglass-Event' => event_type,
        'X-Hourglass-Delivery' => delivery_id || "del_#{SecureRandom.hex(8)}",
        'X-Hourglass-Signature-256' => signature
      }
      headers['X-Hourglass-Timestamp'] = timestamp.to_s if timestamp

      post path, params: body, headers: headers
    end

    def for_integration(integration)
      ->(job_args) { job_args.first == integration.id }
    end

    def add_second_integration(secret: 'whsec_second_server')
      @workspace.hourglass_integrations.create!(
        hourglass_server_id: "srv_#{SecureRandom.hex(4)}",
        hourglass_server_name: 'Other',
        base_url: 'https://hg2.test',
        webhook_secret: secret,
        active: true
      )
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
        post webhooks_hourglass_path(public_id: @integration.public_id),
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

      post webhooks_hourglass_path(public_id: SecureRandom.uuid), params: body, headers: headers
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

      post webhooks_hourglass_path(public_id: @integration.public_id),
           params: body, headers: headers
      assert_response :bad_request
    end

    test 'two integrations in one workspace each verify and process against their own secret' do
      second_secret = 'whsec_second_server'
      second = add_second_integration(secret: second_secret)
      body = '{"x":1}'

      assert_enqueued_with(job: HourglassWebhookProcessorJob, args: for_integration(@integration)) do
        post_webhook(body: body, signature: sign(body), delivery_id: 'del_first')
      end
      assert_response :ok

      assert_enqueued_with(job: HourglassWebhookProcessorJob, args: for_integration(second)) do
        post_webhook(body: body, signature: sign(body, second_secret), delivery_id: 'del_second',
                     path: webhooks_hourglass_path(public_id: second.public_id))
      end
      assert_response :ok

      assert_not_nil @integration.reload.last_webhook_at
      assert_not_nil second.reload.last_webhook_at
    end

    test "one integration's secret does not verify against another integration's URL" do
      second = add_second_integration
      body = '{"x":1}'

      assert_no_difference -> { WebhookDelivery.count } do
        post_webhook(body: body, signature: sign(body), delivery_id: 'del_cross',
                     path: webhooks_hourglass_path(public_id: second.public_id))
      end

      assert_response :unauthorized
    end

    test 'legacy workspace URL resolves when the workspace has exactly one active integration' do
      body = '{"x":1}'

      assert_enqueued_with(job: HourglassWebhookProcessorJob, args: for_integration(@integration)) do
        post_webhook(body: body, signature: sign(body), delivery_id: 'del_legacy',
                     path: webhooks_hourglass_legacy_path(workspace_id: @workspace.id))
      end
      assert_response :ok
    end

    test 'legacy workspace URL ignores inactive integrations when counting' do
      add_second_integration.update!(active: false)
      body = '{"x":1}'

      post_webhook(body: body, signature: sign(body), delivery_id: 'del_legacy_inactive',
                   path: webhooks_hourglass_legacy_path(workspace_id: @workspace.id))
      assert_response :ok
    end

    test 'legacy workspace URL 404s when the workspace has several active integrations' do
      add_second_integration
      body = '{"x":1}'

      assert_no_difference -> { WebhookDelivery.count } do
        post_webhook(body: body, signature: sign(body), delivery_id: 'del_legacy_ambiguous',
                     path: webhooks_hourglass_legacy_path(workspace_id: @workspace.id))
      end
      assert_response :not_found
    end
  end
end
