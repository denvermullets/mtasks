require 'test_helper'

class DisplayPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Prefs User', email: 'display_prefs@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Prefs Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Prefs Team', identifier: 'PRF')
    @team.team_memberships.create!(user: @user)

    sign_in_as(@user)
  end

  test 'saving as default persists show_dependencies' do
    patch team_display_preference_path(@team), params: {
      view_mode: 'board', group_by: 'status', order_by: 'manual', show_dependencies: 'true'
    }

    assert_redirected_to team_issues_path(@team, view_mode: 'board', group_by: 'status', order_by: 'manual',
                                                 show_dependencies: 'true')
    assert UserPreference.for_user_and_team(@user, @team).show_dependencies
  end
end
