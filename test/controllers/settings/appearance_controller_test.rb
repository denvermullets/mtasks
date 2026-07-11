require 'test_helper'

module Settings
  class AppearanceControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(name: 'Theme User', email: 'theme_user@example.com', password: 'password')
      sign_in_as(@user)
    end

    test 'show renders with the default theme' do
      get settings_appearance_path

      assert_response :success
      assert_equal 'default', @user.theme
    end

    test 'update persists the theme and font' do
      patch settings_appearance_path, params: { theme: 'ink', font: 'fira-code' }

      assert_response :no_content
      @user.reload
      assert_equal 'ink', @user.theme
      assert_equal 'fira-code', @user.font
    end

    test 'a saved theme survives a fresh page load' do
      patch settings_appearance_path, params: { theme: 'ocean-floor', font: 'inter' }

      # A fresh, full page load is the path that was broken: the layout must
      # render the persisted theme rather than falling back to 'default'.
      get settings_appearance_path

      assert_response :success
      assert_select 'html[data-theme=?]', 'ocean-floor'
    end

    test 'update preserves unrelated settings keys' do
      @user.update!(settings: { 'team_order' => { 'owned' => [3, 1] } })

      patch settings_appearance_path, params: { theme: 'ash', font: 'inter' }

      @user.reload
      assert_equal 'ash', @user.theme
      assert_equal [3, 1], @user.team_order['owned']
    end

    test 'update rejects an unknown theme' do
      patch settings_appearance_path, params: { theme: 'not-a-theme', font: 'inter' }

      assert_redirected_to settings_appearance_path
      assert_equal 'default', @user.reload.theme
    end

    test 'update rejects an unknown font' do
      patch settings_appearance_path, params: { theme: 'ink', font: 'comic-sans' }

      assert_redirected_to settings_appearance_path
      assert_equal 'inter', @user.reload.font
    end
  end
end
