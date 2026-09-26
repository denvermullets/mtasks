require 'test_helper'

module Settings
  class HomePageControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(name: 'Ryan', email: "home-#{SecureRandom.hex(4)}@example.com", password: 'password',
                           settings: { 'appearance' => { 'theme' => 'dusk' } })
      workspace = Workspace.create!(name: 'Home WS', owner: @user)
      @first_team = workspace.teams.create!(name: 'First', identifier: 'HM1')
      @second_team = workspace.teams.create!(name: 'Second', identifier: 'HM2')
      @first_team.team_memberships.create!(user: @user)
      @second_team.team_memberships.create!(user: @user)
      @dashboard = @user.dashboards.create!(name: 'Today')
      sign_in_as(@user)
    end

    test 'shows the settings page' do
      get settings_home_page_path

      assert_response :success
      assert_match 'Today', response.body
      assert_match 'Second', response.body
    end

    test 'saves a dashboard without touching other settings' do
      patch settings_home_page_path, params: { home: "dashboard:#{@dashboard.id}" }

      assert_redirected_to settings_home_page_path
      assert_equal @dashboard, @user.reload.home_dashboard
      assert_equal 'dusk', @user.theme
    end

    test 'saving a team clears a previously chosen dashboard' do
      @user.update!(settings: @user.settings.merge('home_dashboard_id' => @dashboard.id))

      patch settings_home_page_path, params: { home: "team:#{@second_team.id}" }

      @user.reload
      assert_equal @second_team, @user.home_team
      assert_nil @user.home_dashboard
    end

    test 'blank clears back to the last-used team' do
      @user.update!(settings: @user.settings.merge('home_team_id' => @second_team.id))

      patch settings_home_page_path, params: { home: '' }

      @user.reload
      assert_nil @user.home_team
      assert_not @user.settings.key?('home_team_id')
      assert_not @user.settings.key?('home_dashboard_id')
    end

    test "rejects someone else's dashboard or team" do
      other = User.create!(name: 'Other', email: "other-#{SecureRandom.hex(4)}@example.com", password: 'password')
      foreign_dashboard = other.dashboards.create!(name: 'Theirs')
      foreign_team = Workspace.create!(name: 'Other WS', owner: other).teams.create!(name: 'Theirs', identifier: 'OTH')

      patch settings_home_page_path, params: { home: "dashboard:#{foreign_dashboard.id}" }
      assert_redirected_to settings_home_page_path
      patch settings_home_page_path, params: { home: "team:#{foreign_team.id}" }
      assert_redirected_to settings_home_page_path
      patch settings_home_page_path, params: { home: 'bogus:1' }
      assert_redirected_to settings_home_page_path

      @user.reload
      assert_nil @user.home_dashboard
      assert_nil @user.home_team
    end

    test 'root redirects to the home dashboard' do
      @user.update!(settings: @user.settings.merge('home_dashboard_id' => @dashboard.id))

      get root_path

      assert_redirected_to "/dashboards/#{@dashboard.id}"
    end

    test 'root redirects to the home team' do
      @user.update!(settings: @user.settings.merge('home_team_id' => @second_team.id))

      get root_path

      assert_redirected_to "/teams/#{@second_team.id}/issues"
    end

    test 'root falls back when the home team is archived' do
      @user.update!(settings: @user.settings.merge('home_team_id' => @second_team.id))
      @second_team.update!(archived_at: Time.current)

      get root_path

      assert_redirected_to "/teams/#{@first_team.id}/issues"
    end

    test 'root falls back when the home dashboard is deleted' do
      @user.update!(settings: @user.settings.merge('home_dashboard_id' => @dashboard.id))
      @dashboard.destroy!

      get root_path

      assert_redirected_to "/teams/#{@first_team.id}/issues"
    end
  end
end
