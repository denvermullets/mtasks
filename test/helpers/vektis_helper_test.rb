require 'test_helper'

# The browser handoff. Everything here is a gate: what must be true before a team's publishable key
# is written into the page, and what must never appear there.
class VektisHelperTest < ActionView::TestCase
  include VektisHelper

  PUBLISHABLE = 'vk_pub_dev_local_playground'.freeze
  SERVER_KEY = 'vk_dev_local_internal'.freeze

  setup do
    @user = User.create!(name: 'Vektis User', email: "vektis_helper_#{SecureRandom.hex(4)}@example.com",
                         password: 'password')
    @current_user = @user
    @workspace = Workspace.create!(name: 'Helper WS', owner: @user)
    @team = @workspace.teams.create!(name: 'Helper Team', identifier: 'HLP')
    @current_team = @team
  end

  # The helper reads `authenticated?` / `current_user` / `current_team` from the controller in real
  # requests; supply them here so the test exercises the gating logic alone.
  def authenticated?
    @current_user.present?
  end

  attr_reader :current_user, :current_team

  # Analytics is per-team, so the config surface is a record rather than ENV. Driving the real one
  # is both simpler and more faithful than stubbing Vektis.for.
  def connect!(enabled: true, key: PUBLISHABLE, customer_id: 'helper-tenant', team: @team)
    TeamVektisIntegration.find_or_initialize_by(team: team).tap do |integration|
      integration.enabled = enabled
      integration.publishable_key = key
      integration.server_key = SERVER_KEY
      integration.customer_id = customer_id
      # A non-publishable key is what one of these tests is about, and the model rejects it on
      # save — which is the point: the helper is the second line of defence for a row written
      # around the validation.
      integration.save!(validate: false)
    end
  end

  test 'renders the full attribute set when connected and authenticated' do
    connect!

    attributes = vektis_dataset_attributes

    assert_equal PUBLISHABLE, attributes['data-vektis-key-value']
    assert_equal Rails.application.config.x.vektis.endpoint, attributes['data-vektis-endpoint-value']
    assert_equal 'helper-tenant', attributes['data-vektis-customer-id-value']
    assert_equal @user.id.to_s, attributes['data-vektis-user-id-value']
  end

  test 'renders nothing when the team has no integration at all' do
    assert_empty vektis_dataset_attributes
    assert_equal '', vektis_body_attributes
  end

  test 'renders nothing when the integration is disabled' do
    connect!(enabled: false)

    assert_empty vektis_dataset_attributes
    assert_equal '', vektis_body_attributes
  end

  test 'renders nothing when there is no current team' do
    connect!
    @current_team = nil

    assert_empty vektis_dataset_attributes
  end

  test 'renders nothing for unauthenticated visitors' do
    connect!
    @current_user = nil

    assert_empty vektis_dataset_attributes
  end

  # A full-scope key in the HTML is the worst failure mode here, and the SDK only warns about it
  # client-side. Refuse server-side instead.
  test 'refuses to render a non-publishable key' do
    connect!(key: SERVER_KEY)

    assert_empty vektis_dataset_attributes
  end

  test 'never exposes the full-scope server key' do
    connect!

    assert_not_includes vektis_dataset_attributes.values, SERVER_KEY
  end

  # identify() must carry an opaque ID, never PII.
  test 'sends the numeric user id rather than the email' do
    connect!

    assert_not_includes vektis_dataset_attributes.values, @user.email
  end

  # The whole point of the change: two teams must never be handed each other's key.
  test 'renders the current team own credentials, not another team' do
    other_team = @workspace.teams.create!(name: 'Other', identifier: 'OTH')
    connect!(key: 'vk_pub_team_a', customer_id: 'tenant-a')
    connect!(team: other_team, key: 'vk_pub_team_b', customer_id: 'tenant-b')

    assert_equal 'vk_pub_team_a', vektis_dataset_attributes['data-vektis-key-value']

    @current_team = other_team
    assert_equal 'vk_pub_team_b', vektis_dataset_attributes['data-vektis-key-value']
    assert_equal 'tenant-b', vektis_dataset_attributes['data-vektis-customer-id-value']
  end

  test 'contributes the vektis token when connected and authenticated' do
    connect!

    assert_equal ' vektis', vektis_controller_token
  end

  # The token deliberately does NOT follow the attributes. The SDK is a module singleton that
  # survives Turbo navigation, so the controller has to be present on an unconnected team's page in
  # order to reset() an identity left behind by a connected one — otherwise this team's clicks are
  # billed to the previous team's VEKTIS account.
  test 'attaches the vektis controller on every authenticated page, connected or not' do
    assert_equal ' vektis', vektis_controller_token, 'no record'
    assert_empty vektis_dataset_attributes, 'but still no credentials on the page'

    connect!(enabled: false)
    assert_equal ' vektis', vektis_controller_token, 'disabled'
    assert_empty vektis_dataset_attributes

    connect!(key: SERVER_KEY)
    assert_equal ' vektis', vektis_controller_token, 'non-publishable key'
    assert_empty vektis_dataset_attributes
  end

  # Unauthenticated views have no call sites and no team to reconcile against.
  test 'withholds the vektis token entirely for unauthenticated visitors' do
    connect!
    @current_user = nil

    assert_equal '', vektis_controller_token
    assert_empty vektis_dataset_attributes
  end

  test 'body attributes are html-safe and lead with a separating space' do
    connect!

    rendered = vektis_body_attributes

    assert_predicate rendered, :html_safe?
    assert rendered.start_with?(' '), 'expected a leading space so the tag does not run together'
    assert_includes rendered, %(data-vektis-key-value="#{PUBLISHABLE}")
  end

  test 'escapes attribute values' do
    connect!(key: 'vk_pub_" onload="alert(1)')

    assert_not_includes vektis_body_attributes, 'onload="alert(1)"'
  end
end
