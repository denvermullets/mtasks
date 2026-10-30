require 'test_helper'

module Api
  module V1
    class NotificationsReadAllTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Inbox User', email: "inbox_#{SecureRandom.hex(4)}@example.com",
                             password: 'password')
        @actor = User.create!(name: 'Actor', email: "actor_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @workspace = Workspace.create!(name: 'Inbox WS', owner: @user)
        @team_a = build_team('Alpha', 'ALP')
        @team_b = build_team('Bravo', 'BRV')
        @issue_a = @team_a.issues.create!(title: 'A issue', lane: @team_a.lanes.first, creator: @user)
        @issue_b = @team_b.issues.create!(title: 'B issue', lane: @team_b.lanes.first, creator: @user)
        @headers = api_headers_for(@user)
      end

      def build_team(name, identifier)
        team = @workspace.teams.create!(name: name, identifier: identifier)
        team.team_memberships.create!(user: @user)
        team
      end

      def notify(issue, **attrs)
        @user.notifications.create!({ actor: @actor, issue: issue, action: 'commented', message: 'hi' }.merge(attrs))
      end

      def body
        JSON.parse(response.body)
      end

      def token_headers(token)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      test 'marks all unread read and surfaces them in updated_since' do
        old = notify(@issue_a, updated_at: 1.hour.ago)
        notify(@issue_b)
        since = 1.minute.ago.iso8601(6)

        patch read_all_api_v1_notifications_path, headers: @headers

        assert_response :success
        assert_equal({ 'marked' => 2, 'unread_count' => 0 }, body.slice('marked', 'unread_count'))
        assert response.headers['X-Server-Time'].present?
        assert old.reload.read?

        get api_v1_notifications_path, params: { updated_since: since }, headers: @headers
        assert_includes body['notifications'].pluck('id'), old.id
      end

      test 'team_id limits to one team' do
        a = notify(@issue_a)
        b = notify(@issue_b)

        patch read_all_api_v1_notifications_path({ team_id: @team_a.id }), headers: @headers

        assert_equal 1, body['marked']
        assert_equal 1, body['unread_count']
        assert a.reload.read?
        assert_not b.reload.read?
      end

      test 'team_id outside the token returns 404' do
        other_ws = Workspace.create!(name: 'Other', owner: @user)
        other = other_ws.teams.create!(name: 'Zed', identifier: 'ZED')
        patch read_all_api_v1_notifications_path({ team_id: other.id }), headers: @headers
        assert_response :not_found
      end

      test 'before leaves newer notifications unread' do
        old = notify(@issue_a, created_at: 2.hours.ago)
        fresh = notify(@issue_a)

        patch read_all_api_v1_notifications_path({ before: 1.hour.ago.iso8601(6) }), headers: @headers

        assert_equal 1, body['marked']
        assert old.reload.read?
        assert_not fresh.reload.read?
      end

      test 'invalid before returns 400' do
        patch read_all_api_v1_notifications_path({ before: 'nonsense' }), headers: @headers
        assert_response :bad_request
      end

      test 'team-scoped token only clears its teams' do
        a = notify(@issue_a)
        b = notify(@issue_b)
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team_a])

        patch read_all_api_v1_notifications_path, headers: token_headers(token)

        assert_equal 1, body['marked']
        assert a.reload.read?
        assert_not b.reload.read?
      end

      test 'read-only token is forbidden' do
        n = notify(@issue_a)
        token = ApiToken.generate_for(@user, scopes: %w[read])

        patch read_all_api_v1_notifications_path, headers: token_headers(token)

        assert_response :forbidden
        assert_not n.reload.read?
      end
    end
  end
end
