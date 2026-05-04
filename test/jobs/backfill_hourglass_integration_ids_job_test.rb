require 'test_helper'

class BackfillHourglassIntegrationIdsJobTest < ActiveJob::TestCase
  def with_stubbed_client(client)
    Hourglass::ApiClient.singleton_class.alias_method(:_orig_for_integration, :for_integration)
    Hourglass::ApiClient.define_singleton_method(:for_integration) { |_| client }
    yield
  ensure
    Hourglass::ApiClient.singleton_class.alias_method(:for_integration, :_orig_for_integration)
    Hourglass::ApiClient.singleton_class.send(:remove_method, :_orig_for_integration)
  end

  setup do
    @user = User.create!(name: 'BF', email: 'backfill@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
      webhook_secret: 'old-secret', connected_by_user: @user
    )
  end

  test 'backfills integration_id and refreshes webhook_secret from /me' do
    fake = Object.new
    fake.define_singleton_method(:verify_token) do
      { 'integration' => { 'id' => 42, 'webhook_secret' => 'fresh-secret' } }
    end

    with_stubbed_client(fake) { BackfillHourglassIntegrationIdsJob.perform_now }

    @integration.reload
    assert_equal 42, @integration.hourglass_integration_id
    assert_equal 'fresh-secret', @integration.webhook_secret
  end

  test 'no-ops on integrations that already have ids when /me lacks integration data' do
    @integration.update!(hourglass_integration_id: 99)
    fake = Object.new
    fake.define_singleton_method(:verify_token) { { 'server' => { 'id' => 'srv' } } }

    with_stubbed_client(fake) { BackfillHourglassIntegrationIdsJob.perform_now }

    @integration.reload
    assert_equal 99, @integration.hourglass_integration_id
    assert_equal 'old-secret', @integration.webhook_secret
  end

  test 'swallows api errors and continues to next integration' do
    @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv2', base_url: 'https://hg.test', api_token: 'tok2',
      webhook_secret: 'wh2', connected_by_user: @user
    )
    fake = Object.new
    fake.define_singleton_method(:verify_token) { raise Hourglass::ApiClient::Error, 'boom' }

    assert_nothing_raised do
      with_stubbed_client(fake) { BackfillHourglassIntegrationIdsJob.perform_now }
    end
  end
end
