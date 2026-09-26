require 'test_helper'

module Settings
  class TimeZoneControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(name: 'Ryan', email: "tz-#{SecureRandom.hex(4)}@example.com", password: 'password',
                           settings: { 'appearance' => { 'theme' => 'dusk' } })
      sign_in_as(@user)
    end

    test 'shows the settings page' do
      get settings_path

      assert_response :success
    end

    test 'saves a known zone without touching other settings' do
      patch settings_time_zone_path, params: { time_zone: 'Central Time (US & Canada)' }

      assert_redirected_to settings_path(section: 'time_zone')
      assert_equal 'Central Time (US & Canada)', @user.reload.time_zone
      assert_equal 'dusk', @user.theme
    end

    test 'rejects an unknown zone' do
      patch settings_time_zone_path, params: { time_zone: 'Mars/Olympus' }

      assert_redirected_to settings_path(section: 'time_zone')
      assert_equal 'UTC', @user.reload.time_zone
    end
  end
end
