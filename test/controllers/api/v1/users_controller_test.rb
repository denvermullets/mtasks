require 'test_helper'

module Api
  module V1
    class UsersControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Me User', email: 'me@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Me WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Me Team', identifier: 'METM')
        @team.team_memberships.create!(user: @user)
      end

      def headers_for(token)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      test 'returns the authenticated user and token info' do
        token = ApiToken.generate_for(@user, name: 'CLI Token')

        get api_v1_me_path, headers: headers_for(token)

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal @user.id, json['id']
        assert_equal @user.name, json['name']
        assert_equal @user.email, json['email']
        assert_equal 'CLI Token', json.dig('token', 'name')
        assert_equal %w[read write], json.dig('token', 'scopes')
        assert_nil json.dig('token', 'team_id')
        assert_nil json.dig('token', 'team_ids')
      end

      test 'home_page is null when unset' do
        get api_v1_me_path, headers: api_headers_for(@user)

        assert_response :success
        assert JSON.parse(response.body).key?('home_page')
        assert_nil JSON.parse(response.body)['home_page']
      end

      test 'home_page reports a team' do
        @user.update!(settings: { 'home_team_id' => @team.id })
        get api_v1_me_path, headers: api_headers_for(@user)

        assert_equal({ 'kind' => 'team', 'id' => @team.id }, JSON.parse(response.body)['home_page'])
      end

      test 'home_page reports a saved view' do
        view = @user.saved_views.create!(team: @team, name: 'Mine', query: {})
        @user.update!(settings: { 'home_view_id' => view.id })
        get api_v1_me_path, headers: api_headers_for(@user)

        assert_equal({ 'kind' => 'saved_view', 'id' => view.id }, JSON.parse(response.body)['home_page'])
      end

      test 'home_page reports a dashboard' do
        dashboard = @user.dashboards.create!(name: 'Dash')
        @user.update!(settings: { 'home_dashboard_id' => dashboard.id })
        get api_v1_me_path, headers: api_headers_for(@user)

        assert_equal({ 'kind' => 'dashboard', 'id' => dashboard.id }, JSON.parse(response.body)['home_page'])
      end

      test 'home_page for a team outside a scoped token is null' do
        other = @workspace.teams.create!(name: 'Other', identifier: 'OTHR')
        other.team_memberships.create!(user: @user)
        @user.update!(settings: { 'home_team_id' => other.id })
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team])
        get api_v1_me_path, headers: headers_for(token)

        assert_nil JSON.parse(response.body)['home_page']
      end

      test 'reports team_id for team-scoped tokens' do
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team])

        get api_v1_me_path, headers: headers_for(token)

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal @team.id, json.dig('token', 'team_id')
        assert_equal [@team.id], json.dig('token', 'team_ids')
      end

      def put_home(body, headers: api_headers_for(@user))
        put api_v1_me_home_page_path, params: body.to_json, headers: headers
      end

      test 'PUT home_page sets a team via kind and id' do
        put_home({ kind: 'team', id: @team.id })

        assert_response :success
        assert_equal({ 'kind' => 'team', 'id' => @team.id }, JSON.parse(response.body)['home_page'])
        assert_equal @team, @user.reload.home_team
      end

      test 'PUT home_page sets a saved view via kind and id' do
        view = @user.saved_views.create!(team: @team, name: 'Mine', query: {})
        put_home({ kind: 'saved_view', id: view.id })

        assert_response :success
        assert_equal view, @user.reload.home_view
      end

      test 'PUT home_page sets a dashboard via kind and id' do
        dashboard = @user.dashboards.create!(name: 'Dash')
        put_home({ kind: 'dashboard', id: dashboard.id })

        assert_response :success
        assert_equal dashboard, @user.reload.home_dashboard
      end

      test 'PUT home_page accepts the web string form' do
        view = @user.saved_views.create!(team: @team, name: 'Mine', query: {})
        dashboard = @user.dashboards.create!(name: 'Dash')

        put_home({ home: "team:#{@team.id}" })
        assert_equal @team, @user.reload.home_team
        put_home({ home: "view:#{view.id}" })
        assert_equal view, @user.reload.home_view
        assert_nil @user.home_team
        put_home({ home: "dashboard:#{dashboard.id}" })
        assert_equal dashboard, @user.reload.home_dashboard
        assert_nil @user.home_view
      end

      test 'PUT home_page with a blank value clears it and keeps other settings' do
        @user.update!(settings: { 'home_team_id' => @team.id, 'time_zone' => 'UTC' })

        put_home({ home: '' })

        assert_response :success
        assert_nil JSON.parse(response.body)['home_page']
        assert_equal({ 'time_zone' => 'UTC' }, @user.reload.settings)
      end

      test 'PUT home_page with no kind clears it' do
        @user.update!(settings: { 'home_team_id' => @team.id })

        put_home({})

        assert_response :success
        assert_nil @user.reload.home_team
      end

      test 'PUT home_page rejects inaccessible targets and saves nothing' do
        other_user = User.create!(name: 'Other', email: 'other-home@example.com', password: 'password')
        other_ws = Workspace.create!(name: 'Other WS', owner: other_user)
        foreign_team = other_ws.teams.create!(name: 'Foreign', identifier: 'FRGN')
        foreign_team.team_memberships.create!(user: other_user)
        foreign_view = other_user.saved_views.create!(team: foreign_team, name: 'Theirs', query: {})
        foreign_dash = other_user.dashboards.create!(name: 'Theirs')
        @user.update!(settings: { 'home_team_id' => @team.id })

        [{ kind: 'team', id: foreign_team.id }, { kind: 'saved_view', id: foreign_view.id },
         { kind: 'dashboard', id: foreign_dash.id }, { kind: 'bogus', id: 1 }, { home: 'team:0' }].each do |body|
          put_home(body)

          assert_response :unprocessable_entity
          assert_equal({ 'home_team_id' => @team.id }, @user.reload.settings)
        end
      end

      test 'PUT home_page rejects a team outside a team-scoped token' do
        other = @workspace.teams.create!(name: 'Other', identifier: 'OTHR')
        other.team_memberships.create!(user: @user)
        view = @user.saved_views.create!(team: other, name: 'Other view', query: {})
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team])

        put_home({ kind: 'team', id: other.id }, headers: headers_for(token))
        assert_response :unprocessable_entity
        put_home({ kind: 'saved_view', id: view.id }, headers: headers_for(token))
        assert_response :unprocessable_entity
        assert_nil @user.reload.settings&.dig('home_team_id')

        put_home({ kind: 'team', id: @team.id }, headers: headers_for(token))
        assert_response :success
      end

      test 'PUT home_page needs the write scope' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])

        put_home({ kind: 'team', id: @team.id }, headers: headers_for(token))

        assert_response :forbidden
        assert_nil @user.reload.home_team
      end

      test 'rejects requests without a valid token' do
        get api_v1_me_path
        assert_response :unauthorized
      end

      # by_email
      test 'by_email returns a user who shares a team with caller' do
        teammate = User.create!(name: 'Mate', email: 'mate@example.com', password: 'password')
        @team.team_memberships.create!(user: teammate)

        token = ApiToken.generate_for(@user, name: 't')
        get api_v1_users_by_email_path(email: 'mate@example.com'), headers: headers_for(token)

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal teammate.id, json['id']
        assert_equal 'mate@example.com', json['email']
      end

      test 'by_email is case-insensitive' do
        teammate = User.create!(name: 'Mate', email: 'mate2@example.com', password: 'password')
        @team.team_memberships.create!(user: teammate)

        token = ApiToken.generate_for(@user, name: 't')
        get api_v1_users_by_email_path(email: 'MATE2@example.COM'), headers: headers_for(token)

        assert_response :success
      end

      test 'by_email returns 404 when user shares no team with caller' do
        outsider = User.create!(name: 'Out', email: 'out@example.com', password: 'password')
        Workspace.create!(name: 'Other', owner: outsider)

        token = ApiToken.generate_for(@user, name: 't')
        get api_v1_users_by_email_path(email: 'out@example.com'), headers: headers_for(token)

        assert_response :not_found
      end

      test 'by_email returns 400 with blank email' do
        token = ApiToken.generate_for(@user, name: 't')
        get api_v1_users_by_email_path, headers: headers_for(token)
        assert_response :bad_request
      end

      test 'by_email rejects without a token' do
        get api_v1_users_by_email_path(email: 'me@example.com')
        assert_response :unauthorized
      end
    end
  end
end
