require 'test_helper'

# Vektis.for is the one entry point to a team's analytics configuration. Everything downstream —
# the browser handoff, the emitter, the client, the job — branches on what it returns, so these
# assertions are the contract the rest of the suite assumes.
class VektisTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Config Owner', email: "config-#{SecureRandom.hex(4)}@example.com",
                         password: 'password')
    @workspace = Workspace.create!(name: 'Acme', owner: @user)
    @team = @workspace.teams.create!(name: 'Engineering', identifier: 'ENG')
  end

  test 'a team with no integration record resolves to NullConfig' do
    config = Vektis.for(@team)

    assert_instance_of Vektis::NullConfig, config
    assert_not config.enabled?
    assert_nil config.publishable_key
    assert_nil config.server_key
    assert_nil config.customer_id
  end

  test 'a nil team resolves to NullConfig rather than raising' do
    assert_instance_of Vektis::NullConfig, Vektis.for(nil)
    assert_not Vektis.for(nil).enabled?
  end

  test 'a connected team resolves to a Config carrying its own credentials' do
    TeamVektisIntegration.create!(
      team: @team, enabled: true, publishable_key: 'vk_pub_acme',
      server_key: 'vk_acme_server', customer_id: 'acme-eng'
    )

    config = Vektis.for(@team)

    assert_instance_of Vektis::Config, config
    assert config.enabled?
    assert_equal 'vk_pub_acme', config.publishable_key
    assert_equal 'vk_acme_server', config.server_key
    assert_equal 'acme-eng', config.customer_id
  end

  # A record that exists but is switched off must behave exactly like no record at all — this is
  # the only off switch there is now that the ENV kill switch is gone.
  test 'a disabled record is not enabled even though a Config is returned' do
    TeamVektisIntegration.create!(team: @team, enabled: false, publishable_key: 'vk_pub_acme',
                                  server_key: 'vk_acme_server', customer_id: 'acme-eng')

    assert_not Vektis.for(@team).enabled?
  end

  test 'two teams resolve to their own credentials' do
    other_team = @workspace.teams.create!(name: 'Design', identifier: 'DSGN')
    TeamVektisIntegration.create!(team: @team, enabled: true, publishable_key: 'vk_pub_a',
                                  server_key: 'vk_a', customer_id: 'tenant-a')
    TeamVektisIntegration.create!(team: other_team, enabled: true, publishable_key: 'vk_pub_b',
                                  server_key: 'vk_b', customer_id: 'tenant-b')

    assert_equal 'tenant-a', Vektis.for(@team).customer_id
    assert_equal 'tenant-b', Vektis.for(other_team).customer_id
    assert_equal 'vk_a', Vektis.for(@team).server_key
    assert_equal 'vk_b', Vektis.for(other_team).server_key
  end

  # The endpoint is deployment config, not tenant config: teams supply credentials, not a
  # destination, so both config objects report the same one.
  test 'the endpoint is app-level and identical for every config' do
    TeamVektisIntegration.create!(team: @team, enabled: true, publishable_key: 'vk_pub_acme',
                                  server_key: 'vk_acme_server', customer_id: 'acme-eng')

    assert_equal Rails.application.config.x.vektis.endpoint, Vektis.for(@team).endpoint
    assert_equal Rails.application.config.x.vektis.endpoint, Vektis::NullConfig.new.endpoint
  end
end
