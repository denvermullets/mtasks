require 'test_helper'

module Api
  module V1
    class TeamsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_teams@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'API')
        @team.team_memberships.create!(user: @user)
        @headers = api_headers_for(@user)
      end

      test 'returns unauthorized without token' do
        get api_v1_teams_path, headers: { 'Content-Type' => 'application/json' }
        assert_response :unauthorized
      end

      test 'returns unauthorized with revoked token' do
        @user.api_tokens.active.first.revoke!
        get api_v1_teams_path, headers: @headers
        assert_response :unauthorized
      end

      test 'lists user teams' do
        get api_v1_teams_path, headers: @headers

        assert_response :success
        teams = JSON.parse(response.body)
        assert_equal 1, teams.length
        assert_equal @team.id, teams.first['id']
        assert_equal 'API Team', teams.first['name']
        assert_equal 'API', teams.first['identifier']
      end

      test 'reports owner role for a team the user owns' do
        get api_v1_teams_path, headers: @headers

        assert_equal 'owner', JSON.parse(response.body).first['role']
      end

      test 'owner role wins over an admin membership' do
        @team.team_memberships.find_by(user: @user).update!(role: :admin)
        get api_v1_teams_path, headers: @headers

        assert_equal 'owner', JSON.parse(response.body).first['role']
      end

      test 'reports admin and member roles on teams the user does not own' do
        other_owner = User.create!(name: 'Owner', email: 'owner_teams@example.com', password: 'password')
        other_workspace = Workspace.create!(name: 'Shared Workspace', owner: other_owner)
        admin_team = other_workspace.teams.create!(name: 'Admin Team', identifier: 'ADM')
        member_team = other_workspace.teams.create!(name: 'Member Team', identifier: 'MEM')
        admin_team.team_memberships.create!(user: @user, role: :admin)
        member_team.team_memberships.create!(user: @user)

        get api_v1_teams_path, headers: @headers

        roles = JSON.parse(response.body).to_h { |t| [t['identifier'], t['role']] }
        assert_equal({ 'ADM' => 'admin', 'API' => 'owner', 'MEM' => 'member' }, roles)
      end

      test 'does not include archived teams' do
        @team.archive!
        get api_v1_teams_path, headers: @headers

        assert_response :success
        teams = JSON.parse(response.body)
        assert_equal 0, teams.length
      end

      test 'does not include teams user is not a member of' do
        other_user = User.create!(name: 'Other', email: 'other_teams@example.com', password: 'password')
        other_workspace = Workspace.create!(name: 'Other Workspace', owner: other_user)
        other_workspace.teams.create!(name: 'Other Team', identifier: 'OTH')

        get api_v1_teams_path, headers: @headers

        teams = JSON.parse(response.body)
        assert_equal 1, teams.length
      end
    end
  end
end
