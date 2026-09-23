require 'test_helper'

# Team-admin only, unlike the Hourglass settings screen's membership-level check: these are
# credentials for the team's own VEKTIS account.
module Settings
  class VektisIntegrationsControllerTest < ActionDispatch::IntegrationTest
    include VektisEventTestHelper

    setup do
      @admin = User.create!(name: 'Admin', email: "admin-#{SecureRandom.hex(4)}@example.com",
                            password: 'password')
      @member = User.create!(name: 'Member', email: "member-#{SecureRandom.hex(4)}@example.com",
                             password: 'password')
      @workspace = Workspace.create!(name: 'Acme', owner: @admin)
      @team = @workspace.teams.create!(name: 'Engineering', identifier: 'ENG')
      @team.team_memberships.create!(user: @admin, role: :admin)
      @team.team_memberships.create!(user: @member, role: :member)
    end

    def valid_params(**overrides)
      { team_vektis_integration: {
        enabled: '1', publishable_key: 'vk_pub_live', server_key: 'vk_live', customer_id: 'acme-eng'
      }.merge(overrides) }
    end

    test 'an admin sees the settings page' do
      sign_in_as(@admin)
      get team_settings_vektis_integration_path(@team)

      assert_response :success
    end

    test 'a non-admin member is turned away' do
      sign_in_as(@member)
      get team_settings_vektis_integration_path(@team)

      assert_redirected_to root_path
    end

    test 'a non-admin member cannot write credentials' do
      sign_in_as(@member)
      patch team_settings_vektis_integration_path(@team), params: valid_params

      assert_redirected_to root_path
      assert_nil TeamVektisIntegration.find_by(team: @team)
    end

    test 'an admin connects the team and the connection is stamped' do
      sign_in_as(@admin)
      patch team_settings_vektis_integration_path(@team), params: valid_params

      integration = TeamVektisIntegration.find_by(team: @team)
      assert integration.enabled?
      assert_equal 'acme-eng', integration.customer_id
      assert_equal 'vk_live', integration.server_key
      assert_equal @admin, integration.connected_by_user
      assert_not_nil integration.connected_at
    end

    test 'a full-scope key in the publishable field is rejected' do
      sign_in_as(@admin)
      patch team_settings_vektis_integration_path(@team),
            params: valid_params(publishable_key: 'vk_live_full_scope')

      assert_response :unprocessable_entity
      assert_nil TeamVektisIntegration.find_by(team: @team)
    end

    # The form submits the server key blank whenever the admin is editing something else, and a
    # blank must never wipe a stored credential.
    test 'a blank server key leaves the stored one alone' do
      sign_in_as(@admin)
      patch team_settings_vektis_integration_path(@team), params: valid_params
      patch team_settings_vektis_integration_path(@team),
            params: valid_params(server_key: '', customer_id: 'acme-renamed')

      integration = TeamVektisIntegration.find_by(team: @team)
      assert_equal 'vk_live', integration.server_key
      assert_equal 'acme-renamed', integration.customer_id
    end

    test 'disconnecting removes the record' do
      sign_in_as(@admin)
      patch team_settings_vektis_integration_path(@team), params: valid_params
      delete team_settings_vektis_integration_path(@team)

      assert_nil TeamVektisIntegration.find_by(team: @team)
    end

    # The connect event is emitted under the team's own newly-saved key, and only on the off -> on
    # transition — re-saving a connected integration is an edit, not a new connection.
    test 'connecting emits vektis-integration/link once, under this team' do
      sign_in_as(@admin)
      patch team_settings_vektis_integration_path(@team), params: valid_params

      assert_emitted 'vektis-integration', 'link'
      assert_equal 1, events_for('vektis-integration', 'link').size
      assert_equal [@team.id], emitted_team_ids.uniq
      assert_equal 'acme-eng', event_for('vektis-integration', 'link')['customer_id']
    end

    test 're-saving a connected integration does not emit another link' do
      sign_in_as(@admin)
      patch team_settings_vektis_integration_path(@team), params: valid_params
      patch team_settings_vektis_integration_path(@team), params: valid_params(customer_id: 'renamed')

      assert_equal 1, events_for('vektis-integration', 'link').size
    end

    # Emitted before the destroy, or it would resolve to NullConfig and never be seen.
    test 'disconnecting emits vektis-integration/unlink' do
      sign_in_as(@admin)
      patch team_settings_vektis_integration_path(@team), params: valid_params
      delete team_settings_vektis_integration_path(@team)

      assert_emitted 'vektis-integration', 'unlink'
    end
  end
end
