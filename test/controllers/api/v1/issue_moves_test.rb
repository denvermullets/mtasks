require 'test_helper'

module Api
  module V1
    class IssueMovesTest < ActionDispatch::IntegrationTest
      include VektisEventTestHelper

      setup do
        @user = User.create!(name: 'Mover', email: 'api_mover@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Mover WS', owner: @user)
        @source = build_team('Source', 'SRC')
        @target = build_team('Target', 'TGT')
        @source_lane = @source.lanes.create!(name: 'Backlog', position: 0)
        @target.lanes.create!(name: 'Backlog', position: 0)
        @issue = @source.issues.create!(title: 'Movable', lane: @source_lane, creator: @user)
        @headers = api_headers_for(@user)
      end

      def build_team(name, identifier)
        team = @workspace.teams.create!(name: name, identifier: identifier)
        team.team_memberships.create!(user: @user)
        team
      end

      def headers_with(token)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      def move(target_id, headers: @headers)
        patch move_api_v1_team_issue_path(@source, @issue),
              params: { target_team_id: target_id }.to_json, headers: headers
      end

      test 'move returns the detailed issue with new team and identifier' do
        move(@target.id)

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal @issue.id, body['id']
        assert_equal @target.id, body['team_id']
        assert_equal 1, body['team_number']
        assert_equal 'TGT-1', body['identifier']
        assert_equal @target.id, @issue.reload.team_id
      end

      test 'detached sub-issues show up in the next updated_since pull' do
        child = @source.issues.create!(title: 'Child', lane: @source_lane, creator: @user, parent_issue: @issue)
        child.update_columns(updated_at: 1.day.ago)
        since = 1.hour.ago

        move(@target.id)
        assert_response :success

        get api_v1_team_issues_path(@source), params: { updated_since: since.utc.iso8601(6) }, headers: @headers
        assert_response :success
        assert_includes JSON.parse(response.body).pluck('id'), child.id
        assert_nil child.reload.parent_issue_id
      end

      test 'target team outside a team-scoped token is 404' do
        outside = build_team('Outside', 'OUT')
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@source, @target])

        move(outside.id, headers: headers_with(token))

        assert_response :not_found
        assert_equal @source.id, @issue.reload.team_id
      end

      test 'unknown target team is 404' do
        move(0)
        assert_response :not_found
      end

      test 'read-only token is forbidden' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: ['read'])

        move(@target.id, headers: headers_with(token))

        assert_response :forbidden
      end

      test 'mover failure is 422 with its message' do
        move(@source.id)

        assert_response :unprocessable_entity
        assert_equal 'Issue is already in that team.', JSON.parse(response.body)['errors'].first
      end

      test 'a successful move emits issue-transfer' do
        enable_vektis!(@target)
        clear_enqueued_jobs

        move(@target.id)

        assert_includes pairs, %w[issue-transfer move]
      end
    end
  end
end
