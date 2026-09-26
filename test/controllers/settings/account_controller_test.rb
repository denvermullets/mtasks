require 'test_helper'

module Settings
  class AccountControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(name: 'Ryan', email: "account-#{SecureRandom.hex(4)}@example.com", password: 'password')
      sign_in_as(@user)
    end

    test 'renders every section' do
      get settings_path

      assert_response :success
      %w[appearance home_page team_order time_zone api_tokens].each do |section|
        assert_select "[data-settings-nav-target=panel][data-section=#{section}]"
      end
    end

    test 'opens the requested section' do
      get settings_path(section: 'time_zone')

      assert_select '[data-section=time_zone]:not(.hidden)'
      assert_select '[data-settings-nav-target=panel][data-section=appearance].hidden'
    end

    test 'old standalone pages redirect to their section' do
      get settings_time_zone_path

      assert_redirected_to '/settings?section=time_zone'
    end
  end
end
