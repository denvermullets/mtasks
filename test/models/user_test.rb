require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'downcases and strips email' do
    user = User.new(email: ' DOWNCASED@EXAMPLE.COM ', name: 'Test User')
    assert_equal('downcased@example.com', user.email)
  end

  test 'time zone defaults to UTC and ignores unknown values' do
    user = User.new(settings: {})
    assert_equal 'UTC', user.time_zone

    user.settings = { 'time_zone' => 'Mars/Olympus' }
    assert_equal 'UTC', user.time_zone

    user.settings = { 'time_zone' => 'Eastern Time (US & Canada)' }
    assert_equal 'Eastern Time (US & Canada)', user.time_zone
  end

  test 'sidebar layout pulls grouped teams out of their owned and joined sections' do
    user = User.create!(name: 'Grouper', email: "grouper-#{SecureRandom.hex(4)}@example.com", password: 'password')
    other = User.create!(name: 'Other', email: "other-#{SecureRandom.hex(4)}@example.com", password: 'password')
    owned_a = Workspace.create!(name: 'Mine', owner: user).teams.create!(name: 'A', identifier: 'SGA')
    owned_b = owned_a.workspace.teams.create!(name: 'B', identifier: 'SGB')
    joined = Workspace.create!(name: 'Theirs', owner: other).teams.create!(name: 'C', identifier: 'SGC')
    user.settings = { 'sidebar_groups' => [{ 'id' => 'g1', 'name' => 'Work', 'team_ids' => [joined.id, owned_a.id],
                                             'collapsed' => true }] }

    layout = user.sidebar_layout([owned_a, owned_b, joined])

    group, teams = layout.groups.first
    assert_equal 'Work', group['name']
    assert group['collapsed']
    assert_equal [joined, owned_a], teams
    assert_equal [owned_b], layout.owned
    assert_empty layout.joined
  end
end
