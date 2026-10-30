require 'test_helper'

module Api
  module V1
    class UserDeletedControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'UD User', email: 'api_ud@example.com', password: 'password')
        @other_user = User.create!(name: 'UD Other', email: 'api_ud_other@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'UDA')
        @team2 = @workspace.teams.create!(name: 'T2', identifier: 'UDB')
        [@team, @team2].each do |t|
          t.team_memberships.create!(user: @user)
          t.team_memberships.create!(user: @other_user)
        end
        @headers = api_headers_for(@user)
      end

      def view_for(user, team, name = 'V')
        SavedView.create!(user: user, team: team, name: name, query: {})
      end

      test 'a deleted saved view appears as a SavedView tombstone' do
        view = view_for(@user, @team)
        view_id = view.id
        view.destroy!

        get api_v1_deleted_path, headers: @headers

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal([['SavedView', view_id]], body.map { |e| e.values_at('record_type', 'record_id') })
        assert Time.iso8601(body.first['deleted_at'])
        assert Time.iso8601(response.headers['X-Server-Time'])
      end

      test 'other users deletions never appear' do
        view_for(@other_user, @team).destroy!

        get api_v1_deleted_path, headers: @headers

        assert_response :success
        assert_empty JSON.parse(response.body)
      end

      test 'since filters by deletion time' do
        old = view_for(@user, @team, 'old')
        recent = view_for(@user, @team, 'recent')
        old_id = old.id
        recent_id = recent.id
        old.destroy!
        recent.destroy!
        t = Time.utc(2026, 1, 1, 12)
        PaperTrail::Version.where(item_type: 'SavedView', item_id: old_id).update_all(created_at: t - 1.hour)
        PaperTrail::Version.where(item_type: 'SavedView', item_id: recent_id).update_all(created_at: t + 1.hour)

        get api_v1_deleted_path, params: { since: t.iso8601 }, headers: @headers

        assert_equal [recent_id], JSON.parse(response.body).pluck('record_id')
      end

      test 'invalid since is rejected' do
        get api_v1_deleted_path, params: { since: 'nope' }, headers: @headers

        assert_response :unprocessable_entity
      end

      test 'team-scoped token only sees tombstones from its teams' do
        mine = view_for(@user, @team)
        hidden = view_for(@user, @team2)
        mine_id = mine.id
        hidden.destroy!
        mine.destroy!
        token = ApiToken.generate_for(@user, teams: [@team])

        get api_v1_deleted_path, headers: { 'Authorization' => "Bearer #{token.raw_token}" }

        assert_equal [mine_id], JSON.parse(response.body).pluck('record_id')
      end

      test 'team feed does not include saved views' do
        view_for(@user, @team).destroy!

        get api_v1_team_deleted_path(@team), headers: @headers

        assert_empty JSON.parse(response.body)
      end

      test 'a deleted dashboard group appears as a tombstone' do
        dashboard = @user.dashboards.create!(name: 'D')
        group = dashboard.groups.create!(name: 'G')
        group_id = group.id
        group.destroy!

        get api_v1_deleted_path, headers: @headers

        assert_equal([['DashboardGroup', group_id]],
                     JSON.parse(response.body).map { |e| e.values_at('record_type', 'record_id') })
      end

      test 'a deleted dashboard appears with all its groups' do
        dashboard = @user.dashboards.create!(name: 'D')
        g1 = dashboard.groups.create!(name: 'G1')
        g2 = dashboard.groups.create!(name: 'G2')
        ids = [dashboard.id, g1.id, g2.id]
        dashboard.destroy!

        get api_v1_deleted_path, headers: @headers

        pairs = JSON.parse(response.body).map { |e| e.values_at('record_type', 'record_id') }
        assert_equal [['Dashboard', ids[0]], ['DashboardGroup', ids[1]], ['DashboardGroup', ids[2]]].sort, pairs.sort
      end

      test 'other users dashboard and group deletions never appear' do
        dashboard = @other_user.dashboards.create!(name: 'D')
        dashboard.groups.create!(name: 'G')
        other_group_dash = @other_user.dashboards.create!(name: 'D2')
        other_group_dash.groups.create!(name: 'G2').destroy!
        dashboard.destroy!

        get api_v1_deleted_path, headers: @headers

        assert_empty JSON.parse(response.body)
      end

      test 'missing token is 401' do
        get api_v1_deleted_path

        assert_response :unauthorized
      end
    end
  end
end
