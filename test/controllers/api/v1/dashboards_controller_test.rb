require 'test_helper'

module Api
  module V1
    class DashboardsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Dash User', email: 'api_dash@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Dash Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'Dash Team', identifier: 'ADB')
        @team.team_memberships.create!(user: @user)
        @other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'ADO')
        @other_team.team_memberships.create!(user: @user)

        @dashboard = @user.dashboards.create!(name: 'Mine', position: 1)
        @headers = api_headers_for(@user)
      end

      test 'requires a token' do
        get api_v1_dashboards_path

        assert_response :unauthorized
      end

      test 'lists dashboards with groups and sources in group order' do
        @dashboard.groups.create!(name: 'Second', position: 2)
                  .replace_sources!(team_ids: [@other_team.id], project_ids: [])
        first = @dashboard.groups.create!(name: 'First', position: 1)
        first.replace_sources!(team_ids: [@team.id], project_ids: [], all_team_ids: [@team.id])

        get api_v1_dashboards_path, headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal ['Mine'], json.pluck('name')
        assert_equal %w[First Second], json.first['groups'].pluck('name')
        assert_equal [@team.id], json.first['groups'].first['team_ids']
        assert_equal [@team.id], json.first['groups'].first['all_team_ids']
      end

      test 'omits sources in teams outside the token' do
        group = @dashboard.groups.create!(name: 'G', position: 1)
        group.replace_sources!(team_ids: [@team.id, @other_team.id], project_ids: [])
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team])
        scoped = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        get api_v1_dashboards_path, headers: scoped

        assert_response :success
        assert_equal [@team.id], JSON.parse(response.body).first['groups'].first['team_ids']
      end

      test 'does not expose another user dashboards' do
        other = User.create!(name: 'Other', email: 'api_dash_other@example.com', password: 'password')
        theirs = other.dashboards.create!(name: 'Theirs', position: 1)

        get api_v1_dashboards_path, headers: @headers
        assert_equal ['Mine'], JSON.parse(response.body).pluck('name')

        get api_v1_dashboard_path(theirs), headers: @headers
        assert_response :not_found
        patch api_v1_dashboard_path(theirs), params: { dashboard: { name: 'x' } }.to_json, headers: @headers
        assert_response :not_found
        delete api_v1_dashboard_path(theirs), headers: @headers
        assert_response :not_found
        assert Dashboard.exists?(theirs.id)
      end

      test 'creates a dashboard at the end' do
        post api_v1_dashboards_path, params: { dashboard: { name: 'New', description: 'd' } }.to_json,
                                     headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'New', json['name']
        assert_equal 2, json['position']
        assert_equal [], json['groups']
      end

      test 'rejects a blank name' do
        post api_v1_dashboards_path, params: { dashboard: { name: '' } }.to_json, headers: @headers
        assert_response :unprocessable_entity

        patch api_v1_dashboard_path(@dashboard), params: { dashboard: { name: '' } }.to_json, headers: @headers
        assert_response :unprocessable_entity
      end

      test 'renames and re-describes' do
        patch api_v1_dashboard_path(@dashboard),
              params: { dashboard: { name: 'Renamed', description: 'about' } }.to_json, headers: @headers

        assert_response :success
        assert_equal 'Renamed', JSON.parse(response.body)['name']
        assert_equal 'about', @dashboard.reload.description
      end

      test 'deletes with groups' do
        @dashboard.groups.create!(name: 'G', position: 1)

        assert_difference ['Dashboard.count', 'DashboardGroup.count'], -1 do
          delete api_v1_dashboard_path(@dashboard), headers: @headers
        end

        assert_response :no_content
      end

      test 'read-only token cannot write' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])
        read_only = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        post api_v1_dashboards_path, params: { dashboard: { name: 'x' } }.to_json, headers: read_only
        assert_response :forbidden
        delete api_v1_dashboard_path(@dashboard), headers: read_only
        assert_response :forbidden
        get api_v1_dashboards_path, headers: read_only
        assert_response :success
      end
    end
  end
end
