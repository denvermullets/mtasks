require 'test_helper'

module Api
  module V1
    class SavedViewsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'SV User', email: 'api_sv@example.com', password: 'password')
        @other = User.create!(name: 'SV Other', email: 'api_sv_other@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'SV Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'SV Team', identifier: 'SVA')
        @team2 = @workspace.teams.create!(name: 'SV Team 2', identifier: 'SVB')
        [@team, @team2].each do |t|
          t.team_memberships.create!(user: @user)
          t.team_memberships.create!(user: @other)
        end
        @headers = api_headers_for(@user)
      end

      test 'lists only the current users views across teams' do
        mine = @user.saved_views.create!(team: @team, name: 'Mine', query: { 'group_by' => 'lane' })
        @user.saved_views.create!(team: @team2, name: 'Mine 2')
        @other.saved_views.create!(team: @team, name: 'Theirs')

        get api_v1_saved_views_path, headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal ['Mine', 'Mine 2'].sort, json.pluck('name').sort
        row = json.find { |v| v['id'] == mine.id }
        assert_equal @team.id, row['team_id']
        assert_equal({ 'group_by' => 'lane' }, row['query'])
        assert_equal mine.position, row['position']
      end

      test 'filters by team_id and updated_since' do
        old = @user.saved_views.create!(team: @team, name: 'Old')
        old.update_columns(updated_at: 2.days.ago)
        @user.saved_views.create!(team: @team, name: 'New')
        @user.saved_views.create!(team: @team2, name: 'Other team')

        get api_v1_saved_views_path, params: { team_id: @team.id }, headers: @headers
        assert_equal %w[New Old], JSON.parse(response.body).pluck('name').sort

        get api_v1_saved_views_path, params: { team_id: @team.id, updated_since: 1.day.ago.iso8601 },
                                     headers: @headers
        assert_equal ['New'], JSON.parse(response.body).pluck('name')
      end

      test 'rejects a malformed updated_since' do
        get api_v1_saved_views_path, params: { updated_since: 'nope' }, headers: @headers
        assert_response :unprocessable_entity
      end

      test 'list is limited to teams the token can see' do
        @user.saved_views.create!(team: @team, name: 'Visible')
        @user.saved_views.create!(team: @team2, name: 'Hidden')
        token = ApiToken.generate_for(@user, teams: [@team])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        get api_v1_saved_views_path, headers: headers

        assert_equal ['Visible'], JSON.parse(response.body).pluck('name')
      end

      test 'creates a view, dropping unknown query keys' do
        query = { group_by: 'lane', evil: 'x', lane_ids: '1,2' }
        assert_difference 'SavedView.count', 1 do
          post api_v1_team_saved_views_path(@team),
               params: { saved_view: { name: 'Board', query: query } }.to_json,
               headers: @headers
        end

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'Board', json['name']
        assert_equal({ 'group_by' => 'lane', 'lane_ids' => '1,2' }, json['query'])
        assert_equal @team.id, json['team_id']
        assert_equal 1, json['position']
      end

      test 'accepts a query string and increments position' do
        @user.saved_views.create!(team: @team, name: 'First', position: 4)

        post api_v1_team_saved_views_path(@team),
             params: { saved_view: { name: 'Second', query: '?group_by=assignee&junk=1' } }.to_json,
             headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal({ 'group_by' => 'assignee' }, json['query'])
        assert_equal 5, json['position']
      end

      test 'blank name is 422' do
        post api_v1_team_saved_views_path(@team),
             params: { saved_view: { name: '', query: {} } }.to_json, headers: @headers

        assert_response :unprocessable_entity
      end

      test 'team outside the token is 404' do
        token = ApiToken.generate_for(@user, teams: [@team])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        post api_v1_team_saved_views_path(@team2),
             params: { saved_view: { name: 'X' } }.to_json, headers: headers

        assert_response :not_found
      end

      test 'read-only token cannot create' do
        token = ApiToken.generate_for(@user, scopes: %w[read])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        post api_v1_team_saved_views_path(@team),
             params: { saved_view: { name: 'X' } }.to_json, headers: headers

        assert_response :forbidden
      end

      def token_headers(**)
        token = ApiToken.generate_for(@user, **)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      test 'updates name and query, dropping unknown keys' do
        view = @user.saved_views.create!(team: @team, name: 'Old', query: { 'group_by' => 'lane' })

        patch api_v1_saved_view_path(view),
              params: { saved_view: { name: 'New', query: { priority: '1', evil: 'x' } } }.to_json,
              headers: @headers

        assert_response :ok
        json = JSON.parse(response.body)
        assert_equal 'New', json['name']
        assert_equal({ 'priority' => '1' }, json['query'])
        assert_equal({ 'priority' => '1' }, view.reload.query)
      end

      test 'rename alone keeps the query' do
        view = @user.saved_views.create!(team: @team, name: 'Old', query: { 'group_by' => 'lane' })

        patch api_v1_saved_view_path(view), params: { saved_view: { name: 'Renamed' } }.to_json, headers: @headers

        assert_response :ok
        assert_equal({ 'group_by' => 'lane' }, view.reload.query)
      end

      test 'update with blank name is 422' do
        view = @user.saved_views.create!(team: @team, name: 'Keep')

        patch api_v1_saved_view_path(view), params: { saved_view: { name: '' } }.to_json, headers: @headers

        assert_response :unprocessable_entity
        assert_equal 'Keep', view.reload.name
      end

      test 'deletes a view with 204' do
        view = @user.saved_views.create!(team: @team, name: 'Bye')

        assert_difference 'SavedView.count', -1 do
          delete api_v1_saved_view_path(view), headers: @headers
        end
        assert_response :no_content
      end

      test 'another users view is 404 for update and delete' do
        view = @other.saved_views.create!(team: @team, name: 'Theirs')

        patch api_v1_saved_view_path(view), params: { saved_view: { name: 'X' } }.to_json, headers: @headers
        assert_response :not_found
        assert_no_difference 'SavedView.count' do
          delete api_v1_saved_view_path(view), headers: @headers
        end
        assert_response :not_found
        assert_equal 'Theirs', view.reload.name
      end

      test 'view in a team outside the token is 404' do
        view = @user.saved_views.create!(team: @team2, name: 'Hidden')
        headers = token_headers(teams: [@team])

        patch api_v1_saved_view_path(view), params: { saved_view: { name: 'X' } }.to_json, headers: headers
        assert_response :not_found
        delete api_v1_saved_view_path(view), headers: headers
        assert_response :not_found
        assert SavedView.exists?(view.id)
      end

      test 'read-only token cannot update or delete' do
        view = @user.saved_views.create!(team: @team, name: 'Mine')
        headers = token_headers(scopes: %w[read])

        patch api_v1_saved_view_path(view), params: { saved_view: { name: 'X' } }.to_json, headers: headers
        assert_response :forbidden
        delete api_v1_saved_view_path(view), headers: headers
        assert_response :forbidden
        assert_equal 'Mine', view.reload.name
      end
    end
  end
end
