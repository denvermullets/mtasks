require 'test_helper'

class VektisTest < ActiveSupport::TestCase
  VEKTIS_VARS = %w[
    VEKTIS_ENABLED
    VEKTIS_ENDPOINT
    VEKTIS_PUBLISHABLE_KEY
    VEKTIS_SERVER_KEY
    VEKTIS_CUSTOMER_ID
  ].freeze

  # Save/set/restore ENV around each assertion. Setting a key to nil deletes it,
  # which is what we want for the "unset" cases.
  def with_env(overrides)
    original = VEKTIS_VARS.index_with { |key| ENV.fetch(key, nil) }
    overrides.each { |key, value| ENV[key.to_s] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end

  # Clears every VEKTIS_* var so a developer's own .env can't leak into the
  # default assertions below.
  def with_no_env(&)
    with_env(VEKTIS_VARS.index_with { nil }, &)
  end

  test 'analytics is disabled by default' do
    with_no_env do
      assert_not Vektis.enabled?
    end
  end

  test 'endpoint defaults to local vanalytics, not production' do
    with_no_env do
      assert_equal 'http://localhost:3333/api/v1/events', Vektis.endpoint
    end
  end

  test 'keys default to the vanalytics local seed values' do
    with_no_env do
      assert_equal 'vk_pub_dev_local_playground', Vektis.publishable_key
      assert_equal 'vk_dev_local_internal', Vektis.server_key
    end
  end

  test 'the publishable and server keys are distinct readers' do
    with_env('VEKTIS_PUBLISHABLE_KEY' => 'vk_pub_browser', 'VEKTIS_SERVER_KEY' => 'vk_server') do
      assert_equal 'vk_pub_browser', Vektis.publishable_key
      assert_equal 'vk_server', Vektis.server_key
    end
  end

  test 'customer_id defaults to the local placeholder' do
    with_no_env do
      assert_equal 'mtasks-local-dev', Vektis.customer_id
    end
  end

  test 'every reader honors its env var' do
    with_env(
      'VEKTIS_ENABLED' => 'true',
      'VEKTIS_ENDPOINT' => 'https://events.vektis.io/api/v1/events',
      'VEKTIS_PUBLISHABLE_KEY' => 'vk_pub_live',
      'VEKTIS_SERVER_KEY' => 'vk_live',
      'VEKTIS_CUSTOMER_ID' => 'cus_123'
    ) do
      assert Vektis.enabled?
      assert_equal 'https://events.vektis.io/api/v1/events', Vektis.endpoint
      assert_equal 'vk_pub_live', Vektis.publishable_key
      assert_equal 'vk_live', Vektis.server_key
      assert_equal 'cus_123', Vektis.customer_id
    end
  end

  test 'enabled? parses truthy env values' do
    %w[true TRUE 1 t on yes].each do |value|
      with_env('VEKTIS_ENABLED' => value) do
        assert Vektis.enabled?, "expected #{value.inspect} to enable Vektis"
      end
    end
  end

  test 'enabled? parses falsey env values without returning nil' do
    ['false', 'FALSE', '0', 'f', 'off', ''].each do |value|
      with_env('VEKTIS_ENABLED' => value) do
        assert_equal false, Vektis.enabled?, "expected #{value.inspect} to disable Vektis"
      end
    end
  end
end
