require 'test_helper'
require 'webmock/minitest'

module Hourglass
  class ApiClientTest < ActiveSupport::TestCase
    BASE = 'https://hg.test'.freeze

    def setup
      WebMock.disable_net_connect!
      @client = Hourglass::ApiClient.new(base_url: BASE, api_token: 'tk_abc')
    end

    def teardown
      WebMock.reset!
      WebMock.allow_net_connect!
    end

    test 'verify_token returns parsed JSON on 200 with bearer + accept headers' do
      stub_request(:get, "#{BASE}/api/v1/me")
        .with(headers: { 'Authorization' => 'Bearer tk_abc', 'Accept' => 'application/json' })
        .to_return(status: 200, body: { id: 1, email: 'a@b.test', display_name: 'A' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      assert_equal({ 'id' => 1, 'email' => 'a@b.test', 'display_name' => 'A' }, @client.verify_token)
    end

    test 'raises Unauthorized on 401' do
      stub_request(:get, "#{BASE}/api/v1/me").to_return(status: 401, body: '{}')
      assert_raises(Hourglass::ApiClient::Unauthorized) { @client.verify_token }
    end

    test 'raises Unauthorized on 403' do
      stub_request(:get, "#{BASE}/api/v1/me").to_return(status: 403, body: '{}')
      assert_raises(Hourglass::ApiClient::Unauthorized) { @client.verify_token }
    end

    test 'raises NotFound on 404' do
      stub_request(:get, "#{BASE}/api/v1/messages/9").to_return(status: 404, body: '{}')
      assert_raises(Hourglass::ApiClient::NotFound) { @client.fetch_message(9) }
    end

    test 'raises Error on 500' do
      stub_request(:get, "#{BASE}/api/v1/me").to_return(status: 500, body: '{}')
      assert_raises(Hourglass::ApiClient::Error) { @client.verify_token }
    end

    test 'raises Error on connection failure' do
      stub_request(:get, "#{BASE}/api/v1/me").to_raise(Errno::ECONNREFUSED)
      err = assert_raises(Hourglass::ApiClient::Error) { @client.verify_token }
      assert_match(/connection failed/, err.message)
    end

    test 'discover_channels! requires server_id' do
      err = assert_raises(Hourglass::ApiClient::Error) { @client.discover_channels! }
      assert_match(/server_id missing/, err.message)
    end

    test 'discover_channels! returns array from server response' do
      @client.server_id = 'srv_1'
      stub_request(:get, "#{BASE}/api/v1/servers/srv_1/channels")
        .to_return(status: 200, body: [{ id: 1 }, { id: 2 }, { id: 3 }].to_json,
                   headers: { 'Content-Type' => 'application/json' })

      channels = @client.discover_channels!
      assert_equal 3, channels.size
    end

    test 'post_channel_message posts JSON body tagged with source: mtasks' do
      stub_request(:post, "#{BASE}/api/v1/channels/c1/messages")
        .with(body: { body: 'hi', data: { source: 'mtasks' } }.to_json)
        .to_return(status: 201, body: { id: 99, body: 'hi' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      res = @client.post_channel_message('c1', body: 'hi')
      assert_equal 99, res['id']
    end

    test 'post_thread_message posts JSON body tagged with source: mtasks' do
      stub_request(:post, "#{BASE}/api/v1/messages/m1/replies")
        .with(body: { body: 'hi', data: { source: 'mtasks' } }.to_json)
        .to_return(status: 201, body: { id: 100, body: 'hi' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      res = @client.post_thread_message('m1', body: 'hi')
      assert_equal 100, res['id']
    end

    test 'identify_user URL-escapes the email' do
      stub_request(:get, "#{BASE}/api/v1/users/lookup?email=a%2Bb%40c.test")
        .to_return(status: 200, body: { id: 5 }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      res = @client.identify_user(email: 'a+b@c.test')
      assert_equal 5, res['id']
    end
  end
end
