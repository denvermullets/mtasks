require 'test_helper'

module Api
  module V1
    class MembersControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_members@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'Member Team', identifier: 'MBT')
        @team.team_memberships.create!(user: @user)
        @headers = api_headers_for(@user)
      end

      test 'lists team members' do
        get api_v1_team_members_path(@team), headers: @headers

        assert_response :success
        members = JSON.parse(response.body)
        assert_equal 1, members.length
        assert_equal @user.id, members.first['id']
        assert_equal @user.name, members.first['name']
        assert_equal @user.email, members.first['email']
      end
    end
  end
end
