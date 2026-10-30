require 'test_helper'

module Api
  module V1
    class NotificationsUnreadCountTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Badge User', email: "badge_#{SecureRandom.hex(4)}@example.com",
                             password: 'password')
        @actor = User.create!(name: 'Actor', email: "actor_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @workspace = Workspace.create!(name: 'Badge WS', owner: @user)
        @team_a = build_team('Alpha', 'ALP')
        @team_b = build_team('Bravo', 'BRV')
        @issue_a = @team_a.issues.create!(title: 'A issue', lane: @team_a.lanes.first, creator: @user)
        @issue_b = @team_b.issues.create!(title: 'B issue', lane: @team_b.lanes.first, creator: @user)
      end

      def build_team(name, identifier)
        team = @workspace.teams.create!(name: name, identifier: identifier)
        team.team_memberships.create!(user: @user)
        team
      end

      def notify(issue, user: @user, **attrs)
        user.notifications.create!({ actor: @actor, issue: issue, action: 'commented', message: 'hi' }.merge(attrs))
      end

      def body
        JSON.parse(response.body)
      end

      test 'requires a token' do
        get unread_count_api_v1_notifications_path
        assert_response :unauthorized
      end

      test 'returns the unread count and server time' do
        notify(@issue_a)
        notify(@issue_b)
        notify(@issue_a, read_at: Time.current)

        get unread_count_api_v1_notifications_path, headers: api_headers_for(@user)

        assert_response :success
        assert_equal 2, body['unread_count']
        assert body['server_time'].present?
      end

      test 'does not count other users notifications' do
        other = User.create!(name: 'Other', email: "o_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @team_a.team_memberships.create!(user: other)
        notify(@issue_a, user: other)

        get unread_count_api_v1_notifications_path, headers: api_headers_for(@user)

        assert_equal 0, body['unread_count']
      end

      test 'team-scoped token counts only its teams' do
        notify(@issue_a)
        notify(@issue_b)
        token = ApiToken.generate_for(@user, name: 'A only', teams: [@team_a])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        get unread_count_api_v1_notifications_path, headers: headers

        assert_equal 1, body['unread_count']
      end
    end
  end
end
