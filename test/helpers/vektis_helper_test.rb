require 'test_helper'

class VektisHelperTest < ActionView::TestCase
  include VektisHelper

  PUBLISHABLE = 'vk_pub_dev_local_playground'.freeze

  setup do
    @user = User.create!(name: 'Vektis User', email: 'vektis_helper@example.com', password: 'password')
    @current_user = @user
  end

  # The helper reads `authenticated?` / `current_user` from the controller in
  # real requests; supply them here so the test exercises the gating logic alone.
  def authenticated?
    @current_user.present?
  end

  attr_reader :current_user

  # Vektis reads ENV on every call rather than memoizing, so driving the real
  # config surface is both simpler and more faithful than stubbing it. Rails
  # parallelizes with processes, so per-process ENV mutation stays isolated.
  def with_env(vars)
    original = vars.keys.index_with { |key| ENV.fetch(key, nil) }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_analytics(enabled: 'true', key: PUBLISHABLE, &)
    with_env({ 'VEKTIS_ENABLED' => enabled, 'VEKTIS_PUBLISHABLE_KEY' => key }, &)
  end

  test 'renders the full attribute set when enabled and authenticated' do
    with_analytics do
      attributes = vektis_dataset_attributes

      assert_equal PUBLISHABLE, attributes['data-vektis-key-value']
      assert_equal Vektis.endpoint, attributes['data-vektis-endpoint-value']
      assert_equal Vektis.customer_id, attributes['data-vektis-customer-id-value']
      assert_equal @user.id.to_s, attributes['data-vektis-user-id-value']
    end
  end

  test 'renders nothing when analytics is disabled' do
    with_analytics(enabled: 'false') do
      assert_empty vektis_dataset_attributes
      assert_equal '', vektis_body_attributes
    end
  end

  test 'renders nothing when the enabled flag is unset' do
    with_analytics(enabled: nil) do
      assert_empty vektis_dataset_attributes
    end
  end

  # `VEKTIS_ENABLED=` in a .env file casts to nil, not false.
  test 'renders nothing when the enabled flag is blank' do
    with_analytics(enabled: '') do
      assert_empty vektis_dataset_attributes
    end
  end

  test 'renders nothing for unauthenticated visitors' do
    @current_user = nil

    with_analytics do
      assert_empty vektis_dataset_attributes
    end
  end

  # A full-scope key in the HTML is the worst failure mode here, and the SDK
  # only warns about it client-side. Refuse server-side instead.
  test 'refuses to render a non-publishable key' do
    with_analytics(key: 'vk_dev_local_internal') do
      assert_empty vektis_dataset_attributes
    end
  end

  test 'never exposes the full-scope server key' do
    with_analytics do
      assert_not_includes vektis_dataset_attributes.values, Vektis.server_key
    end
  end

  # identify() must carry an opaque ID, never PII.
  test 'sends the numeric user id rather than the email' do
    with_analytics do
      assert_not_includes vektis_dataset_attributes.values, @user.email
    end
  end

  test 'contributes the vektis token when enabled and authenticated' do
    with_analytics do
      assert_equal ' vektis', vektis_controller_token
    end
  end

  # The token and the attributes must appear together or not at all — Stimulus
  # reads the values only off an element carrying the matching data-controller.
  test 'withholds the vektis token wherever it withholds the attributes' do
    with_analytics(enabled: 'false') { assert_equal '', vektis_controller_token }
    with_analytics(enabled: nil) { assert_equal '', vektis_controller_token }
    with_analytics(key: 'vk_dev_local_internal') { assert_equal '', vektis_controller_token }

    @current_user = nil
    with_analytics { assert_equal '', vektis_controller_token }
  end

  test 'body attributes are html-safe and lead with a separating space' do
    with_analytics do
      rendered = vektis_body_attributes

      assert_predicate rendered, :html_safe?
      assert rendered.start_with?(' '), 'expected a leading space so the tag does not run together'
      assert_includes rendered, %(data-vektis-key-value="#{PUBLISHABLE}")
    end
  end

  test 'escapes attribute values' do
    with_analytics(key: 'vk_pub_" onload="alert(1)') do
      assert_not_includes vektis_body_attributes, 'onload="alert(1)"'
    end
  end
end
