require 'test_helper'

class HourglassIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'HG User', email: 'hg_int@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'HG Workspace', owner: @user)
  end

  test 'creates with required fields' do
    integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv_1',
      base_url: 'https://hg.test'
    )
    assert integration.persisted?
    assert integration.active?
  end

  test 'requires hourglass_server_id' do
    integration = @workspace.hourglass_integrations.new(base_url: 'https://hg.test')
    assert_not integration.valid?
    assert_includes integration.errors[:hourglass_server_id], "can't be blank"
  end

  test 'requires base_url' do
    integration = @workspace.hourglass_integrations.new(hourglass_server_id: 'srv_1')
    assert_not integration.valid?
    assert_includes integration.errors[:base_url], "can't be blank"
  end

  test 'unique on workspace_id + hourglass_server_id' do
    @workspace.hourglass_integrations.create!(hourglass_server_id: 'srv_dup', base_url: 'https://hg.test')
    dup = @workspace.hourglass_integrations.build(hourglass_server_id: 'srv_dup', base_url: 'https://hg.test')
    assert_not dup.valid?
  end

  test 'allows same server_id across different workspaces' do
    other_user = User.create!(name: 'Other', email: 'hg_int_other@example.com', password: 'password')
    other_ws = Workspace.create!(name: 'Other WS', owner: other_user)

    @workspace.hourglass_integrations.create!(hourglass_server_id: 'srv_shared', base_url: 'https://hg.test')
    other = other_ws.hourglass_integrations.create!(hourglass_server_id: 'srv_shared', base_url: 'https://hg.test')
    assert other.persisted?
  end

  test 'active scope excludes inactive' do
    on  = @workspace.hourglass_integrations.create!(hourglass_server_id: 'srv_on',  base_url: 'https://hg.test')
    off = @workspace.hourglass_integrations.create!(hourglass_server_id: 'srv_off', base_url: 'https://hg.test',
                                                    active: false)

    ids = @workspace.hourglass_integrations.active.pluck(:id)
    assert_includes ids, on.id
    assert_not_includes ids, off.id
  end
end
