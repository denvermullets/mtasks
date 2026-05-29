require 'test_helper'

class HourglassUserResolverTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Casey', email: 'resolver@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'HUR')
    @team.team_memberships.create!(user: @user)
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
      webhook_secret: 'wh', connected_by_user: @user
    )
  end

  def with_stubbed_client(client)
    Hourglass::ApiClient.singleton_class.alias_method(:_orig_for_integration, :for_integration)
    Hourglass::ApiClient.define_singleton_method(:for_integration) { |_| client }
    yield
  ensure
    Hourglass::ApiClient.singleton_class.alias_method(:for_integration, :_orig_for_integration)
    Hourglass::ApiClient.singleton_class.send(:remove_method, :_orig_for_integration)
  end

  test 'cache hit returns user without API call' do
    HourglassUserMap.create!(
      mtasks_user: @user, hourglass_user_id: 'hu_1', email: @user.email, last_synced_at: Time.current
    )
    raise_client = Object.new
    raise_client.define_singleton_method(:identify_user) { |**| raise 'should not be called' }

    with_stubbed_client(raise_client) do
      result = HourglassUserResolver.call(email: @user.email, integration: @integration)
      assert_equal @user, result.user
      assert_equal 'Casey', result.display_name
    end
  end

  test 'lazy_fetch off returns fallback Result on cache miss' do
    raise_client = Object.new
    raise_client.define_singleton_method(:identify_user) { |**| raise 'should not be called' }

    with_stubbed_client(raise_client) do
      result = HourglassUserResolver.call(email: 'nobody@example.com', integration: @integration)
      assert_nil result.user
      assert_equal 'nobody', result.display_name
    end
  end

  test 'lazy_fetch true persists map row when local user matches' do
    fake = Object.new
    fake.define_singleton_method(:identify_user) do |email:|
      { 'id' => 'hu_99', 'display_name' => 'Casey M', 'email' => email }
    end

    with_stubbed_client(fake) do
      assert_difference -> { HourglassUserMap.count }, 1 do
        result = HourglassUserResolver.call(email: @user.email, integration: @integration, lazy_fetch: true)
        assert_equal @user, result.user
        assert_equal 'Casey M', result.display_name
      end
    end
  end

  test 'lazy_fetch true does not persist map row when no local user' do
    fake = Object.new
    fake.define_singleton_method(:identify_user) do |email:|
      { 'id' => 'hu_xx', 'display_name' => 'Stranger', 'email' => email }
    end

    with_stubbed_client(fake) do
      assert_no_difference -> { HourglassUserMap.count } do
        result = HourglassUserResolver.call(email: 'stranger@example.com', integration: @integration, lazy_fetch: true)
        assert_nil result.user
        assert_equal 'Stranger', result.display_name
      end
    end
  end

  test 'lazy_fetch ApiClient error returns fallback Result' do
    fake = Object.new
    fake.define_singleton_method(:identify_user) { |**| raise Hourglass::ApiClient::Error, 'boom' }

    with_stubbed_client(fake) do
      result = HourglassUserResolver.call(email: 'boom@example.com', integration: @integration, lazy_fetch: true)
      assert_nil result.user
      assert_equal 'boom', result.display_name
    end
  end
end
