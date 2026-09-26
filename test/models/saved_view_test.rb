require 'test_helper'

class SavedViewTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'View User', email: "sv-#{SecureRandom.hex(4)}@example.com", password: 'password')
    @team = Workspace.create!(name: 'View WS', owner: @user).teams.create!(name: 'View Team', identifier: 'SVW')
    @team.team_memberships.create!(user: @user)
  end

  test 'name is required and limited to 80 characters' do
    assert_not @user.saved_views.new(team: @team, name: '').valid?
    assert_not @user.saved_views.new(team: @team, name: 'a' * 81).valid?
    assert @user.saved_views.new(team: @team, name: 'a' * 80).valid?
  end

  test 'query_from keeps board params and drops everything else' do
    query = SavedView.query_from('?group_by=assignee&lane_ids=1,2&completed_filter=&utm_source=x&priority=high')

    assert_equal({ 'group_by' => 'assignee', 'lane_ids' => '1,2', 'completed_filter' => '', 'priority' => 'high' },
                 query)
  end

  test 'path replays the query on the team board' do
    view = @user.saved_views.create!(team: @team, name: 'Mine', query: { 'assignee_ids' => '4' })

    assert_equal "/teams/#{@team.id}/issues?assignee_ids=4", view.path
    assert_equal "/teams/#{@team.id}/issues", @user.saved_views.create!(team: @team, name: 'All').path
  end
end
