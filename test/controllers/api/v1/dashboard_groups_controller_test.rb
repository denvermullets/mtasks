require 'test_helper'

module Api
  module V1
    class DashboardGroupsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Grp User', email: 'api_grp@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Grp Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'Grp Team', identifier: 'AGA')
        @team.team_memberships.create!(user: @user)
        @project = @team.projects.create!(name: 'Mine P')
        @label = @team.labels.create!(name: 'bug', color: '#ff0000')

        @stranger = User.create!(name: 'Stranger', email: 'api_grp_stranger@example.com', password: 'password')
        @foreign_ws = Workspace.create!(name: 'Foreign WS', owner: @stranger)
        @foreign_team = @foreign_ws.teams.create!(name: 'Foreign', identifier: 'AGF')
        @foreign_team.team_memberships.create!(user: @stranger)
        @foreign_project = @foreign_team.projects.create!(name: 'Foreign P')
        @foreign_label = @foreign_team.labels.create!(name: 'nope', color: '#00ff00')

        @dashboard = @user.dashboards.create!(name: 'Mine', position: 1)
        @headers = api_headers_for(@user)
      end

      test 'creates a group at the end with sources' do
        @dashboard.groups.create!(name: 'Existing', position: 1)

        post api_v1_dashboard_groups_path(@dashboard), headers: @headers, params: {
          dashboard_group: { name: 'New', color: DashboardGroup::COLORS.first, team_ids: [@team.id],
                             project_ids: [@project.id], label_ids: [@label.id],
                             all_team_ids: [@team.id], all_project_ids: [@project.id] }
        }.to_json

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'New', json['name']
        assert_equal 2, json['position']
        assert_equal [@team.id], json['team_ids']
        assert_equal [@project.id], json['project_ids']
        assert_equal [@label.id], json['label_ids']
        assert_equal [@team.id], json['all_team_ids']
        assert_equal [@project.id], json['all_project_ids']
      end

      test 'drops inaccessible sources on create' do
        post api_v1_dashboard_groups_path(@dashboard), headers: @headers, params: {
          dashboard_group: { name: 'G', team_ids: [@team.id, @foreign_team.id],
                             project_ids: [@project.id, @foreign_project.id],
                             label_ids: [@label.id, @foreign_label.id],
                             all_team_ids: [@foreign_team.id] }
        }.to_json

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal [@team.id], json['team_ids']
        assert_equal [@project.id], json['project_ids']
        assert_equal [@label.id], json['label_ids']
        assert_equal [], json['all_team_ids']
        assert_equal 3, DashboardGroupSource.where(dashboard_group_id: json['id']).count
      end

      test 'a team-scoped token drops sources outside its teams' do
        other = @workspace.teams.create!(name: 'Other', identifier: 'AGO')
        other.team_memberships.create!(user: @user)
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team])
        scoped = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        body = { dashboard_group: { name: 'G', team_ids: [@team.id, other.id] } }.to_json
        post api_v1_dashboard_groups_path(@dashboard), headers: scoped, params: body

        assert_response :created
        assert_equal [@team.id], JSON.parse(response.body)['team_ids']
      end

      test 'rejects a blank name' do
        assert_no_difference 'DashboardGroup.count' do
          post api_v1_dashboard_groups_path(@dashboard), headers: @headers,
                                                         params: { dashboard_group: { name: '' } }.to_json
        end

        assert_response :unprocessable_entity
      end

      test 'updates attributes and replaces sources, dropping inaccessible ones' do
        group = @dashboard.groups.create!(name: 'Old', position: 1)
        group.replace_sources!(team_ids: [@team.id], project_ids: [])

        patch api_v1_dashboard_group_path(@dashboard, group), headers: @headers, params: {
          dashboard_group: { name: 'Renamed', description: 'about', project_ids: [@project.id, @foreign_project.id] }
        }.to_json

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 'Renamed', json['name']
        assert_equal 'about', json['description']
        assert_equal [], json['team_ids']
        assert_equal [@project.id], json['project_ids']
      end

      test 'destroys a group' do
        group = @dashboard.groups.create!(name: 'G', position: 1)

        assert_difference 'DashboardGroup.count', -1 do
          delete api_v1_dashboard_group_path(@dashboard, group), headers: @headers
        end

        assert_response :no_content
      end

      test 'a group on another user dashboard is not found' do
        theirs = @stranger.dashboards.create!(name: 'Theirs', position: 1)
        group = theirs.groups.create!(name: 'G', position: 1)

        post api_v1_dashboard_groups_path(theirs), headers: @headers,
                                                   params: { dashboard_group: { name: 'x' } }.to_json
        assert_response :not_found
        patch api_v1_dashboard_group_path(theirs, group), headers: @headers,
                                                          params: { dashboard_group: { name: 'x' } }.to_json
        assert_response :not_found
        delete api_v1_dashboard_group_path(theirs, group), headers: @headers
        assert_response :not_found
        assert DashboardGroup.exists?(group.id)
      end

      test 'a group id from a different dashboard of mine is not found' do
        elsewhere = @user.dashboards.create!(name: 'Elsewhere', position: 2).groups.create!(name: 'E', position: 1)

        delete api_v1_dashboard_group_path(@dashboard, elsewhere), headers: @headers

        assert_response :not_found
      end

      test 'read-only token cannot write groups' do
        group = @dashboard.groups.create!(name: 'G', position: 1)
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])
        read_only = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        post api_v1_dashboard_groups_path(@dashboard), headers: read_only,
                                                       params: { dashboard_group: { name: 'x' } }.to_json
        assert_response :forbidden
        patch api_v1_dashboard_group_path(@dashboard, group), headers: read_only,
                                                              params: { dashboard_group: { name: 'x' } }.to_json
        assert_response :forbidden
        delete api_v1_dashboard_group_path(@dashboard, group), headers: read_only
        assert_response :forbidden
      end
    end
  end
end
