require 'test_helper'

# The validations exist to stop two specific mistakes reaching production: a full-scope key
# rendered into every page, and an enabled integration with no tenant to file events under.
class TeamVektisIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Admin', email: "tvi-#{SecureRandom.hex(4)}@example.com",
                         password: 'password')
    @workspace = Workspace.create!(name: 'Acme', owner: @user)
    @team = @workspace.teams.create!(name: 'Engineering', identifier: 'ENG')
  end

  def integration(**overrides)
    TeamVektisIntegration.new({
      team: @team, enabled: true, publishable_key: 'vk_pub_live',
      server_key: 'vk_live', customer_id: 'acme-eng'
    }.merge(overrides))
  end

  test 'a fully connected integration is valid' do
    assert integration.valid?
  end

  # A draft row must be savable so an admin can fill the form in over more than one save without
  # being blocked, and so `find_or_initialize_by` in the controller has something to render.
  test 'a disabled integration needs no credentials at all' do
    record = TeamVektisIntegration.new(team: @team, enabled: false)

    assert record.valid?, record.errors.full_messages.inspect
  end

  test 'enabling requires every credential' do
    record = TeamVektisIntegration.new(team: @team, enabled: true)

    assert_not record.valid?
    assert_includes record.errors.attribute_names, :publishable_key
    assert_includes record.errors.attribute_names, :server_key
    assert_includes record.errors.attribute_names, :customer_id
  end

  # The publishable key is rendered into the page for every viewer, so a full-scope key here would
  # hand a write-capable credential to anyone who views source.
  test 'the publishable key must carry the publishable prefix' do
    record = integration(publishable_key: 'vk_live_full_scope')

    assert_not record.valid?
    assert_includes record.errors.full_messages.join, 'publishable'
  end

  test 'customer_id is capped at the wire field length' do
    record = integration(customer_id: 'a' * (Vektis::Taxonomy::MAX_FIELD_LENGTH + 1))

    assert_not record.valid?
    assert_includes record.errors.attribute_names, :customer_id
  end

  test 'a team may hold only one integration' do
    TeamVektisIntegration.create!(team: @team, enabled: false)

    assert_raises(ActiveRecord::RecordNotUnique) do
      TeamVektisIntegration.new(team: @team, enabled: false).save(validate: false)
    end
  end

  # Explicitly allowed: several mtasks teams may report into one VEKTIS customer.
  test 'two teams may share a customer_id' do
    other_team = @workspace.teams.create!(name: 'Design', identifier: 'DSGN')
    TeamVektisIntegration.create!(team: @team, enabled: true, publishable_key: 'vk_pub_a',
                                  server_key: 'vk_a', customer_id: 'shared-tenant')

    shared = TeamVektisIntegration.new(team: other_team, enabled: true,
                                       publishable_key: 'vk_pub_b', server_key: 'vk_b',
                                       customer_id: 'shared-tenant')

    assert shared.valid?, shared.errors.full_messages.inspect
  end
end
