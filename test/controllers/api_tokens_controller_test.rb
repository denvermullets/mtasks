require 'test_helper'

class ApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Token User', email: 'web_tokens@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Token Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Token Team', identifier: 'TKN')
    @team.team_memberships.create!(user: @user)

    @other_user = User.create!(name: 'Other', email: 'other_web@example.com', password: 'password')
    @other_workspace = Workspace.create!(name: 'Other WS', owner: @other_user)
    @other_team = @other_workspace.teams.create!(name: 'Other Team', identifier: 'OTH')

    sign_in_as(@user)
  end

  test 'index shows page when no token exists' do
    get api_tokens_path
    assert_response :success
  end

  test 'new shows form' do
    get new_api_token_path
    assert_response :success
  end

  test 'create generates a named token with default read+write' do
    assert_difference 'ApiToken.count', 1 do
      post api_tokens_path, params: { api_token: { name: 'Slack', permission: 'write' } }
    end

    token = @user.api_tokens.active.order(:created_at).last
    assert_equal 'Slack', token.name
    assert_equal %w[read write], token.scopes
    assert_nil token.team_id

    assert_redirected_to api_tokens_path
    follow_redirect!
    assert_response :success
  end

  test 'create accepts read-only permission' do
    post api_tokens_path, params: { api_token: { name: 'Chat', permission: 'read' } }

    token = @user.api_tokens.active.order(:created_at).last
    assert_equal %w[read], token.scopes
  end

  test 'create scopes token to team the user belongs to' do
    post api_tokens_path, params: { api_token: { name: 'Team token', permission: 'read', team_id: @team.id } }

    token = @user.api_tokens.active.order(:created_at).last
    assert_equal @team.id, token.team_id
  end

  test 'create ignores team_id for teams the user does not belong to' do
    post api_tokens_path, params: { api_token: { name: 'Foreign', permission: 'read', team_id: @other_team.id } }

    token = @user.api_tokens.active.order(:created_at).last
    assert_nil token.team_id
  end

  test 'create requires name' do
    assert_no_difference 'ApiToken.count' do
      post api_tokens_path, params: { api_token: { name: '', permission: 'write' } }
    end

    assert_redirected_to new_api_token_path
  end

  test 'create does not revoke existing tokens' do
    existing = ApiToken.generate_for(@user, name: 'Existing')

    post api_tokens_path, params: { api_token: { name: 'New', permission: 'write' } }

    existing.reload
    assert_not existing.revoked?
    assert_equal 2, @user.api_tokens.active.count
  end

  test 'destroy revokes the token' do
    token = ApiToken.generate_for(@user, name: 'To revoke')

    delete api_token_path(token)

    assert_redirected_to api_tokens_path
    token.reload
    assert token.revoked?
  end
end
