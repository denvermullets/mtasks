require 'test_helper'

module Api
  module V1
    class NotificationsControllerTest < ActionDispatch::IntegrationTest
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

      def notify(issue, user: @user, **attrs)
        user.notifications.create!({ actor: @actor, issue: issue, action: 'commented', message: 'hi' }.merge(attrs))
      end

      def body
        JSON.parse(response.body)
      end

      test 'requires a token' do
        get api_v1_notifications_path
        assert_response :unauthorized
      end

      test 'lists newest first in an envelope with meta' do
        first = notify(@issue_a)
        second = notify(@issue_a, read_at: Time.current)

        get api_v1_notifications_path, headers: @headers

        assert_response :success
        assert_equal [second.id, first.id], body['notifications'].pluck('id')
        assert_equal 1, body['meta']['unread_count']
        assert body['meta']['server_time'].present?
        n = body['notifications'].last
        assert_equal 'Actor', n['actor']['name']
        assert_equal @issue_a.identifier, n['issue']['identifier']
        assert_equal @team_a.id, n['issue']['team_id']
      end

      test 'never returns another users notifications' do
        other = User.create!(name: 'Other', email: "o_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @team_a.team_memberships.create!(user: other)
        notify(@issue_a, user: other)

        get api_v1_notifications_path, headers: @headers

        assert_empty body['notifications']
        assert_equal 0, body['meta']['unread_count']
      end

      test 'limit and before_id backfill' do
        ns = Array.new(3) { notify(@issue_a) }

        get api_v1_notifications_path, params: { limit: 2 }, headers: @headers
        assert_equal [ns[2].id, ns[1].id], body['notifications'].pluck('id')

        get api_v1_notifications_path, params: { limit: 2, before_id: ns[1].id }, headers: @headers
        assert_equal [ns[0].id], body['notifications'].pluck('id')
      end

      test 'updated_since returns only changed notifications' do
        old = notify(@issue_a)
        old.update_columns(updated_at: 2.hours.ago)
        fresh = notify(@issue_a)

        get api_v1_notifications_path, params: { updated_since: 1.hour.ago.iso8601 }, headers: @headers

        assert_equal [fresh.id], body['notifications'].pluck('id')
      end

      test 'unread=1 filters to unread' do
        notify(@issue_a, read_at: Time.current)
        unread = notify(@issue_a)

        get api_v1_notifications_path, params: { unread: 1 }, headers: @headers

        assert_equal [unread.id], body['notifications'].pluck('id')
      end

      test 'team-scoped token excludes other teams from list and count' do
        keep = notify(@issue_a)
        notify(@issue_b)
        token = ApiToken.generate_for(@user, name: 'A only', teams: [@team_a])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        get api_v1_notifications_path, headers: headers

        assert_equal [keep.id], body['notifications'].pluck('id')
        assert_equal 1, body['meta']['unread_count']
      end

      test 'If-None-Match on an unchanged inbox returns 304' do
        notify(@issue_a)

        get api_v1_notifications_path, headers: @headers
        etag = response.headers['ETag']
        assert etag.present?

        get api_v1_notifications_path, headers: @headers.merge('If-None-Match' => etag)
        assert_response :not_modified
      end

      test 'etag changes when a notification is marked read' do
        n = notify(@issue_a)
        get api_v1_notifications_path, headers: @headers
        etag = response.headers['ETag']

        n.update!(read_at: Time.current)
        get api_v1_notifications_path, headers: @headers.merge('If-None-Match' => etag)

        assert_response :success
      end

      test 'read marks the notification read and returns it' do
        n = notify(@issue_a)
        patch read_api_v1_notification_path(n), headers: @headers

        assert_response :success
        assert_equal n.id, body['id']
        assert_not_nil body['read_at']
        assert n.reload.read?
      end

      test 'read is idempotent and leaves read_at and updated_at unchanged' do
        n = notify(@issue_a)
        patch read_api_v1_notification_path(n), headers: @headers
        first = body['read_at']
        updated = n.reload.updated_at

        patch read_api_v1_notification_path(n), headers: @headers

        assert_response :success
        assert_equal first, body['read_at']
        assert_equal updated, n.reload.updated_at
      end

      test 'read bumps updated_at so it shows up in updated_since' do
        n = notify(@issue_a)
        n.update_columns(updated_at: 1.hour.ago)
        since = 1.minute.ago.iso8601(6)

        patch read_api_v1_notification_path(n), headers: @headers
        get api_v1_notifications_path(updated_since: since), headers: @headers

        assert_equal([n.id], body['notifications'].map { |x| x['id'] })
      end

      test 'read 404s for another users notification' do
        other = User.create!(name: 'Other', email: "o_#{SecureRandom.hex(4)}@example.com", password: 'password')
        n = notify(@issue_a, user: other)
        patch read_api_v1_notification_path(n), headers: @headers

        assert_response :not_found
        assert_not n.reload.read?
      end

      test 'read 404s outside a team-scoped token' do
        n = notify(@issue_b)
        token = ApiToken.generate_for(@user, name: 'A only', teams: [@team_a])
        patch read_api_v1_notification_path(n),
              headers: { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        assert_response :not_found
        assert_not n.reload.read?
      end

      test 'read requires write scope' do
        n = notify(@issue_a)
        token = ApiToken.generate_for(@user, name: 'ro', scopes: ['read'])
        patch read_api_v1_notification_path(n),
              headers: { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        assert_response :forbidden
        assert_not n.reload.read?
      end
    end
  end
end
