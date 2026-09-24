require 'test_helper'

class NavigationTrailTest < ActiveSupport::TestCase
  test 'revisiting a page drops everything after it' do
    trail = NavigationTrail.new([])
    trail.visit('/teams/1/issues').visit('/teams/1/issues/5').visit('/teams/1/issues/6').visit('/teams/1/issues/5')

    assert_equal ['/teams/1/issues', '/teams/1/issues/5'], trail.entries
  end

  test 'same page with a different query replaces the entry' do
    trail = NavigationTrail.new(['/teams/1/issues', '/teams/1/issues/5'])
    trail.visit('/teams/1/issues?lane_ids=2')

    assert_equal ['/teams/1/issues?lane_ids=2'], trail.entries
  end

  test 'project tabs count as the same page' do
    trail = NavigationTrail.new(['/teams/1/projects/3'])
    trail.visit('/teams/1/projects/3/activity')

    assert_equal ['/teams/1/projects/3/activity'], trail.entries
  end

  test 'ignores untracked pages' do
    trail = NavigationTrail.new(['/teams/1/issues', '/teams/1/issues/new', 'https://evil.example/teams/1/issues'])
    trail.visit('/teams/1/issues/5/edit')

    assert_equal ['/teams/1/issues'], trail.entries
  end

  test 'switching teams starts a fresh trail' do
    trail = NavigationTrail.new(['/teams/1/issues', '/teams/1/issues/5'])
    trail.visit('/teams/2/issues')

    assert_equal ['/teams/2/issues'], trail.entries
  end

  test 'caps entries and strips over-long queries' do
    trail = NavigationTrail.new([])
    (1..10).each { |id| trail.visit("/teams/1/issues/#{id}") }
    trail.visit("/teams/1/issues?q=#{'x' * NavigationTrail::MAX_PATH_LENGTH}")

    assert_equal NavigationTrail::MAX_ENTRIES, trail.entries.size
    assert_equal '/teams/1/issues', trail.entries.last
  end

  test 'back_from skips the current page and anything after it' do
    trail = NavigationTrail.new(['/teams/1/issues?lane_ids=2', '/teams/1/issues/5', '/teams/1/issues/6'])

    assert_equal '/teams/1/issues?lane_ids=2', trail.back_from('/teams/1/issues/5', team_id: 1)
    assert_equal '/teams/1/issues/5', trail.back_from('/teams/1/issues/6', team_id: 1)
    assert_equal '/teams/1/issues/6', trail.back_from('/teams/1/issues/7', team_id: 1)
    assert_equal '/teams/1/issues/6', trail.back_from(nil, team_id: 1)
    assert_nil trail.back_from(nil, team_id: 2)
  end
end
