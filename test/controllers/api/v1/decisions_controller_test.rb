require 'test_helper'

module Api
  module V1
    class DecisionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Dec User', email: "dec_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @workspace = Workspace.create!(name: 'Dec WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Dec Team', identifier: 'DCT')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'Backlog', position: 0)
        @issue = @team.issues.create!(title: 'Pinnable', lane: @lane, creator: @user)
        @project = @team.projects.create!(name: 'Pinnable Project', status: 'backlog')
        @headers = api_headers_for(@user)
      end

      def base_payload
        {
          hourglass_message_id: "hg-#{SecureRandom.hex(4)}",
          body_snapshot: 'We agreed to ship Tuesday',
          pinned_at: Time.current.iso8601
        }
      end

      # ---- create on issue ----
      test 'POST issue decision creates and returns 201' do
        assert_difference -> { Decision.count }, 1 do
          post api_v1_team_issue_decisions_path(@team, @issue),
               params: base_payload.to_json, headers: @headers
        end

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal @issue.id, json['issue_id']
        assert_equal @team.id, json['team_id']
        assert_nil json['project_id']
      end

      test 'POST issue decision with pinned_by_email links the user when teammate' do
        teammate = User.create!(name: 'M', email: "mate_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @team.team_memberships.create!(user: teammate)

        post api_v1_team_issue_decisions_path(@team, @issue),
             params: base_payload.merge(pinned_by_email: teammate.email).to_json,
             headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal teammate.id, json.dig('pinned_by_user', 'id')
      end

      # ---- create on project ----
      test 'POST project decision creates with project_id, no issue_id' do
        post api_v1_team_project_decisions_path(@team, @project),
             params: base_payload.to_json, headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal @project.id, json['project_id']
        assert_nil json['issue_id']
      end

      # ---- idempotency ----
      test 'replay with same Idempotency-Key returns existing row, no DB delta' do
        payload = base_payload.to_json
        headers = @headers.merge('Idempotency-Key' => 'dec-1')

        post api_v1_team_issue_decisions_path(@team, @issue), params: payload, headers: headers
        first_id = JSON.parse(response.body)['id']
        assert_response :created

        assert_no_difference -> { Decision.count } do
          post api_v1_team_issue_decisions_path(@team, @issue), params: payload, headers: headers
        end

        assert_response :ok
        assert_equal first_id, JSON.parse(response.body)['id']
      end

      test 'replay with same hourglass_message_id (no Idempotency-Key) returns existing' do
        payload = base_payload.to_json

        post api_v1_team_issue_decisions_path(@team, @issue), params: payload, headers: @headers
        first_id = JSON.parse(response.body)['id']
        assert_response :created

        assert_no_difference -> { Decision.count } do
          post api_v1_team_issue_decisions_path(@team, @issue), params: payload, headers: @headers
        end

        assert_response :ok
        assert_equal first_id, JSON.parse(response.body)['id']
      end

      # ---- destroy ----
      test 'DELETE marks unpinned_at and returns 204' do
        post api_v1_team_issue_decisions_path(@team, @issue), params: base_payload.to_json, headers: @headers
        decision_id = JSON.parse(response.body)['id']

        delete api_v1_team_issue_decision_path(@team, @issue, decision_id), headers: @headers
        assert_response :no_content

        assert_not_nil Decision.find(decision_id).unpinned_at
      end

      test 'DELETE on already-unpinned is idempotent (204), unpinned_at unchanged' do
        post api_v1_team_issue_decisions_path(@team, @issue), params: base_payload.to_json, headers: @headers
        decision_id = JSON.parse(response.body)['id']
        decision = Decision.find(decision_id)
        decision.update!(unpinned_at: 1.hour.ago)
        original = decision.unpinned_at

        delete api_v1_team_issue_decision_path(@team, @issue, decision_id), headers: @headers
        assert_response :no_content
        assert_equal original.to_i, decision.reload.unpinned_at.to_i
      end

      # ---- auth / scopes ----
      test 'no token returns 401' do
        post api_v1_team_issue_decisions_path(@team, @issue),
             params: base_payload.to_json, headers: { 'Content-Type' => 'application/json' }
        assert_response :unauthorized
      end

      test 'read-only token returns 403 on POST' do
        ro = ApiToken.generate_for(@user, name: 'ro', scopes: %w[read])
        headers = { 'Authorization' => "Bearer #{ro.raw_token}", 'Content-Type' => 'application/json' }

        post api_v1_team_issue_decisions_path(@team, @issue),
             params: base_payload.to_json, headers: headers
        assert_response :forbidden
      end

      test 'cross-team team_id returns 404' do
        outsider = User.create!(name: 'Out', email: "out_#{SecureRandom.hex(4)}@example.com", password: 'password')
        out_ws = Workspace.create!(name: 'Out WS', owner: outsider)
        out_team = out_ws.teams.create!(name: 'Out', identifier: 'OUT')
        out_lane = out_team.lanes.create!(name: 'Backlog', position: 0)
        out_issue = out_team.issues.create!(title: 't', lane: out_lane, creator: outsider)

        post api_v1_team_issue_decisions_path(out_team, out_issue),
             params: base_payload.to_json, headers: @headers
        assert_response :not_found
      end

      test 'unknown issue_id under valid team returns 404' do
        post api_v1_team_issue_decisions_path(@team, 9_999_999),
             params: base_payload.to_json, headers: @headers
        assert_response :not_found
      end
    end
  end
end
