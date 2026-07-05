require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test 'new' do
    get new_session_path
    assert_response :success
  end

  test 'create with valid credentials' do
    post session_path, params: { email: @user.email, password: 'password' }

    assert_redirected_to '/teams/new'
    assert cookies[:mtasks_session_id]
  end

  test 'create redirects to the board when the user has an active team' do
    workspace = @user.owned_workspaces.create!(name: 'WS')
    team = workspace.teams.create!(name: 'Team One', identifier: 'ENG', owner: @user)
    team.team_memberships.create!(user: @user)

    post session_path, params: { email: @user.email, password: 'password' }

    assert_redirected_to "/teams/#{team.id}/issues"
  end

  test 'create skips archived teams and redirects to team creation' do
    workspace = @user.owned_workspaces.create!(name: 'WS')
    team = workspace.teams.create!(name: 'Archived', identifier: 'ARC', owner: @user)
    team.team_memberships.create!(user: @user)
    team.archive!

    post session_path, params: { email: @user.email, password: 'password' }

    assert_redirected_to '/teams/new'
  end

  test 'create with invalid credentials' do
    post session_path, params: { email: @user.email, password: 'wrong' }

    assert_redirected_to new_session_path
    assert_nil cookies[:mtasks_session_id]
  end

  test 'destroy' do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:mtasks_session_id]
  end
end
