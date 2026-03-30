require 'test_helper'

module Api
  module V1
    class LanesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_lanes@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'Lane Team', identifier: 'LNT')
        @team.team_memberships.create!(user: @user)
        @headers = api_headers_for(@user)
      end

      test 'lists lanes ordered by position' do
        # Team already has default lanes from after_create callback
        get api_v1_team_lanes_path(@team), headers: @headers

        assert_response :success
        lanes = JSON.parse(response.body)
        assert lanes.length >= 1
        assert lanes.first.key?('id')
        assert lanes.first.key?('name')
        assert lanes.first.key?('position')
        assert lanes.first.key?('color')

        positions = lanes.map { |l| l['position'] }
        assert_equal positions.sort, positions
      end
    end
  end
end
