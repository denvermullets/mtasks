require 'test_helper'
require 'webmock/minitest'

module Hourglass
  class WebhookDispatcherTest < ActiveSupport::TestCase
    BASE = 'https://hg.test'.freeze
    WHURL = "#{BASE}/webhooks/mtasks/42".freeze

    setup do
      WebMock.disable_net_connect!
      @user = User.create!(name: 'WD', email: 'wh_dispatch@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @user)
      @integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv', hourglass_integration_id: 42,
        base_url: BASE, api_token: 'tok', webhook_secret: 'shhh',
        connected_by_user: @user
      )
    end

    teardown do
      WebMock.reset!
      WebMock.allow_net_connect!
    end

    test 'POSTs signed JSON to /webhooks/mtasks/:id with X-Mtasks-* headers' do
      stub_request(:post, WHURL).to_return(status: 200, body: '{}')

      result = Hourglass::WebhookDispatcher.call(
        integration: @integration, event_type: 'link.created',
        data: { link_type: 'issue_thread', mtasks_issue_id: 1 }
      )

      assert_equal 200, result.status
      assert_requested(:post, WHURL) do |req|
        body = JSON.parse(req.body)
        sig = req.headers['X-Mtasks-Signature-256']
        expected = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', 'shhh', req.body)}"

        body['event'] == 'link.created' &&
          body['data']['link_type'] == 'issue_thread' &&
          req.headers['X-Mtasks-Event'] == 'link.created' &&
          req.headers['X-Mtasks-Delivery'].present? &&
          sig == expected
      end
    end

    test 'raises Unauthorized on 401' do
      stub_request(:post, WHURL).to_return(status: 401)
      assert_raises(Hourglass::ApiClient::Unauthorized) do
        Hourglass::WebhookDispatcher.call(
          integration: @integration, event_type: 'link.created', data: {}
        )
      end
    end

    test 'raises NotFound on 404' do
      stub_request(:post, WHURL).to_return(status: 404)
      assert_raises(Hourglass::ApiClient::NotFound) do
        Hourglass::WebhookDispatcher.call(
          integration: @integration, event_type: 'link.created', data: {}
        )
      end
    end

    test 'raises Error when integration has no hourglass_integration_id' do
      @integration.update!(hourglass_integration_id: nil)
      assert_raises(Hourglass::ApiClient::Error) do
        Hourglass::WebhookDispatcher.call(
          integration: @integration, event_type: 'link.created', data: {}
        )
      end
    end
  end
end
