require 'test_helper'

class SavedViewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Ryan', email: "views-#{SecureRandom.hex(4)}@example.com", password: 'password')
    @team = Workspace.create!(name: 'Views WS', owner: @user).teams.create!(name: 'Views', identifier: 'VWS')
    @team.team_memberships.create!(user: @user)
    sign_in_as(@user)
  end

  test 'creates a view from the current query string and lands on it' do
    assert_difference -> { @user.saved_views.count }, 1 do
      post team_saved_views_path(@team),
           params: { saved_view: { name: 'My bugs', query: '?assignee_ids=1&view_mode=board&junk=1' } }
    end

    view = @user.saved_views.last
    assert_equal({ 'assignee_ids' => '1', 'view_mode' => 'board' }, view.query)
    assert_equal @team, view.team
    assert_redirected_to view.path
  end

  test 'a blank name is rejected' do
    assert_no_difference -> { SavedView.count } do
      post team_saved_views_path(@team), params: { saved_view: { name: '', query: '?q=x' } }
    end
    assert_redirected_to team_issues_path(@team, q: 'x')
  end

  test 'update re-captures the current filters' do
    view = @user.saved_views.create!(team: @team, name: 'Mine', query: { 'group_by' => 'status' })

    patch team_saved_view_path(@team, view), params: { saved_view: { query: '?group_by=priority' } }

    assert_equal({ 'group_by' => 'priority' }, view.reload.query)
    assert_equal 'Mine', view.name
  end

  test 'destroy removes the view' do
    view = @user.saved_views.create!(team: @team, name: 'Mine')

    assert_difference -> { SavedView.count }, -1 do
      delete team_saved_view_path(@team, view)
    end
    assert_redirected_to team_issues_path(@team)
  end

  test "cannot touch someone else's view" do
    other = User.create!(name: 'Other', email: "views-other-#{SecureRandom.hex(4)}@example.com", password: 'password')
    @team.team_memberships.create!(user: other)
    theirs = other.saved_views.create!(team: @team, name: 'Theirs')

    delete team_saved_view_path(@team, theirs)

    assert_response :not_found
    assert SavedView.exists?(theirs.id)
  end

  test 'issues board lists the team views and the sidebar shows them' do
    @user.saved_views.create!(team: @team, name: 'Sprint board', query: { 'view_mode' => 'board' })

    get team_issues_path(@team)

    assert_response :success
    assert_match 'Sprint board', response.body
    assert_match 'Save current view', response.body
  end
end
