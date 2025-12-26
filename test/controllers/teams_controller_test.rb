require 'test_helper'

class TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test 'new shows team creation form' do
    get new_team_path
    assert_response :success
  end

  test 'create with workspace params creates workspace and team for new user' do
    # Ensure user has no workspaces
    @user.owned_workspaces.destroy_all

    assert_difference ['Workspace.count', 'Team.count', 'TeamMembership.count'], 1 do
      post teams_path, params: {
        workspace: { name: 'Test Workspace' },
        team: {
          name: 'Engineering',
          identifier: 'ENG',
          description: 'Engineering team'
        }
      }
    end

    assert_redirected_to root_path
    assert_equal 'Team created successfully!', flash[:notice]

    team = Team.last
    assert_equal 'Engineering', team.name
    assert_equal 'ENG', team.identifier
    assert_equal 'Engineering team', team.description
    assert_includes team.users, @user
    assert_equal 'Test Workspace', team.workspace.name
  end

  test 'create without workspace params uses existing workspace' do
    # Create a workspace for the user first
    workspace = @user.owned_workspaces.create!(name: 'Existing Workspace')

    assert_difference ['Team.count', 'TeamMembership.count'], 1 do
      assert_no_difference 'Workspace.count' do
        post teams_path, params: {
          team: {
            name: 'Marketing',
            identifier: 'MKT',
            description: 'Marketing team'
          }
        }
      end
    end

    assert_redirected_to root_path
    assert_equal 'Team created successfully!', flash[:notice]

    team = Team.last
    assert_equal 'Marketing', team.name
    assert_equal 'MKT', team.identifier
    assert_equal workspace, team.workspace
    assert_includes team.users, @user
  end

  test 'create with invalid team params renders form with errors' do
    @user.owned_workspaces.create!(name: 'Test Workspace')

    assert_no_difference ['Team.count', 'TeamMembership.count'] do
      post teams_path, params: {
        team: {
          name: '', # Invalid - blank name
          identifier: 'ENG'
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test 'create with invalid identifier shows validation error' do
    @user.owned_workspaces.create!(name: 'Test Workspace')

    assert_no_difference ['Team.count', 'TeamMembership.count'] do
      post teams_path, params: {
        team: {
          name: 'Engineering',
          identifier: 'TOOLONG' # Invalid - must be exactly 3 characters
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test 'create with duplicate identifier shows validation error' do
    workspace = @user.owned_workspaces.create!(name: 'Test Workspace')
    workspace.teams.create!(name: 'Team One', identifier: 'ENG')

    assert_no_difference ['Team.count', 'TeamMembership.count'] do
      post teams_path, params: {
        team: {
          name: 'Team Two',
          identifier: 'ENG' # Duplicate identifier
        }
      }
    end

    assert_response :unprocessable_entity
  end
end
