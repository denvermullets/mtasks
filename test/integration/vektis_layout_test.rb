require 'test_helper'

# End-to-end check that the Vektis attributes actually reach the rendered <body>.
# The helper unit test covers the gating logic; this covers the ERB wiring.
class VektisLayoutTest < ActionDispatch::IntegrationTest
  PUBLISHABLE = 'vk_pub_dev_local_playground'.freeze
  CUSTOMER_ID = 'layout-tenant'.freeze

  setup do
    @user = User.create!(name: 'Vektis Layout',
                         email: "vektis_layout_#{SecureRandom.hex(4)}@example.com",
                         password: 'password')
    @workspace = Workspace.create!(name: 'Vektis Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Vektis Team', identifier: 'VKL')
    @team.team_memberships.create!(user: @user)
    @team.lanes.create!(name: 'Backlog', position: 0)
  end

  # Connects the team to its own VEKTIS account, which is what puts the attributes on the page.
  def with_analytics(enabled: true, key: PUBLISHABLE)
    TeamVektisIntegration.find_or_initialize_by(team: @team).update!(
      enabled: enabled, publishable_key: key, server_key: 'vk_layout_server',
      customer_id: CUSTOMER_ID
    )
    yield
  end

  test 'renders vektis attributes on the body for an authenticated page' do
    sign_in_as(@user)

    with_analytics do
      get team_issues_path(@team)

      assert_response :success
      assert_select 'body[data-vektis-key-value=?]', PUBLISHABLE
      assert_select 'body[data-vektis-customer-id-value=?]', CUSTOMER_ID
      assert_select 'body[data-vektis-user-id-value=?]', @user.id.to_s
      assert_select 'body[data-vektis-endpoint-value=?]', Rails.application.config.x.vektis.endpoint
    end
  end

  # The SDK's tryAutoInit() scans for a literal `data-vektis-key` at module
  # evaluation and warns VEK_TRK_AUTOINIT_UNAVAILABLE when it finds one it
  # cannot act on. Stimulus `-value` naming is what keeps that scan from
  # matching, so the bare attribute name must never appear.
  test 'does not emit the SDK auto-init attribute names' do
    sign_in_as(@user)

    with_analytics do
      get team_issues_path(@team)

      assert_no_match(/data-vektis-key=/, response.body)
      assert_select 'body[data-vektis-key]', false
    end
  end

  test 'attaches the vektis controller alongside the existing data-controller list' do
    sign_in_as(@user)

    with_analytics do
      get team_issues_path(@team)

      assert_select 'body[data-controller*=?]', 'keyboard-shortcuts'
      assert_select 'body[data-controller*=?]', 'sidebar'
      assert_select 'body[data-controller*=?]', 'notification-drawer'
      assert_select 'body[data-controller*=?]', 'vektis'
    end
  end

  # No credentials on the page, but the controller is still attached — it is the only thing that
  # can reset() an SDK identity left over from a team that IS connected.
  test 'renders no credentials but keeps the controller when analytics is disabled' do
    sign_in_as(@user)

    with_analytics(enabled: false) do
      get team_issues_path(@team)

      assert_response :success
      assert_no_match(/data-vektis-key-value/, response.body)
      assert_select 'body[data-controller*=?]', 'vektis'
    end
  end

  # A team with no integration record at all is the default state.
  test 'renders no credentials but keeps the controller when the team has never connected' do
    sign_in_as(@user)

    get team_issues_path(@team)

    assert_response :success
    assert_no_match(/data-vektis-key-value/, response.body)
    assert_select 'body[data-controller*=?]', 'vektis'
  end

  test 'never puts the publishable key in the HTML for unauthenticated visitors' do
    with_analytics do
      get root_path

      assert_no_match(/data-vektis/, response.body)
      assert_no_match(/vk_pub_/, response.body)
      assert_select 'body[data-controller*=?]', 'vektis', false
    end
  end
end
