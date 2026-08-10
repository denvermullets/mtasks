require 'test_helper'

# End-to-end check that the Vektis attributes actually reach the rendered <body>.
# The helper unit test covers the gating logic; this covers the ERB wiring.
class VektisLayoutTest < ActionDispatch::IntegrationTest
  PUBLISHABLE = 'vk_pub_dev_local_playground'.freeze

  setup do
    @user = User.create!(name: 'Vektis Layout', email: 'vektis_layout@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Vektis Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Vektis Team', identifier: 'VKL')
    @team.team_memberships.create!(user: @user)
    @team.lanes.create!(name: 'Backlog', position: 0)
  end

  def with_analytics(enabled: 'true', key: PUBLISHABLE)
    vars = { 'VEKTIS_ENABLED' => enabled, 'VEKTIS_PUBLISHABLE_KEY' => key }
    original = vars.keys.index_with { |name| ENV.fetch(name, nil) }
    vars.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    yield
  ensure
    original.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  test 'renders vektis attributes on the body for an authenticated page' do
    sign_in_as(@user)

    with_analytics do
      get team_issues_path(@team)

      assert_response :success
      assert_select 'body[data-vektis-key-value=?]', PUBLISHABLE
      assert_select 'body[data-vektis-customer-id-value=?]', Vektis.customer_id
      assert_select 'body[data-vektis-user-id-value=?]', @user.id.to_s
      assert_select 'body[data-vektis-endpoint-value=?]', Vektis.endpoint
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

  test 'emits nothing when analytics is disabled' do
    sign_in_as(@user)

    with_analytics(enabled: 'false') do
      get team_issues_path(@team)

      assert_response :success
      assert_no_match(/data-vektis/, response.body)
      assert_select 'body[data-controller*=?]', 'vektis', false
    end
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
