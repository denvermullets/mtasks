require 'test_helper'

class ApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Token User', email: 'web_tokens@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Token Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Token Team', identifier: 'TKN')
    @team.team_memberships.create!(user: @user)
    sign_in_as(@user)
  end

  test 'index shows page when no token exists' do
    get api_tokens_path
    assert_response :success
  end

  test 'create generates a new token' do
    assert_difference 'ApiToken.count', 1 do
      post api_tokens_path
    end

    assert_redirected_to api_tokens_path
    follow_redirect!
    assert_response :success
  end

  test 'create revokes existing token and generates new one' do
    ApiToken.generate_for(@user)

    assert_no_difference 'ApiToken.active.count' do
      post api_tokens_path
    end

    assert_equal 1, @user.api_tokens.active.count
  end

  test 'destroy revokes the token' do
    token = ApiToken.generate_for(@user)

    delete api_token_path(token)

    assert_redirected_to api_tokens_path
    token.reload
    assert token.revoked?
  end
end
