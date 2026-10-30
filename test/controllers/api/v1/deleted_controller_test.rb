require 'test_helper'

module Api
  module V1
    class DeletedControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Del User', email: 'api_del@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'ADL')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'Backlog', position: 0)
        @other_team = @workspace.teams.create!(name: 'O', identifier: 'ADO')
        @other_team.team_memberships.create!(user: @user)
        @other_lane = @other_team.lanes.create!(name: 'Backlog', position: 0)
        @headers = api_headers_for(@user)
      end

      test 'a deleted issue appears as an Issue tombstone' do
        issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
        issue_id = issue.id
        issue.destroy!

        get api_v1_team_deleted_path(@team), headers: @headers

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal([{ 'record_type' => 'Issue', 'record_id' => issue_id }], body.map do |e|
          e.slice('record_type', 'record_id')
        end)
        assert Time.iso8601(body.first['deleted_at'])
        assert Time.iso8601(response.headers['X-Server-Time'])
      end

      test 'a deleted project appears as a Project tombstone' do
        project = @team.projects.create!(name: 'P')
        project_id = project.id
        project.destroy!

        get api_v1_team_deleted_path(@team), headers: @headers

        body = JSON.parse(response.body)
        assert_equal([['Project', project_id]], body.map { |e| e.values_at('record_type', 'record_id') })
      end

      test 'since filters by deletion time' do
        old = @team.issues.create!(title: 'old', lane: @lane, creator: @user)
        recent = @team.issues.create!(title: 'recent', lane: @lane, creator: @user)
        old_id = old.id
        recent_id = recent.id
        old.destroy!
        recent.destroy!
        t = Time.utc(2026, 1, 1, 12)
        PaperTrail::Version.where(item_type: 'Issue', item_id: old_id,
                                  event: 'destroy').update_all(created_at: t - 1.hour)
        PaperTrail::Version.where(item_type: 'Issue', item_id: recent_id,
                                  event: 'destroy').update_all(created_at: t + 1.hour)

        get api_v1_team_deleted_path(@team), params: { since: t.iso8601 }, headers: @headers

        assert_equal [recent_id], JSON.parse(response.body).pluck('record_id')
      end

      test 'invalid since is rejected' do
        get api_v1_team_deleted_path(@team), params: { since: 'nope' }, headers: @headers

        assert_response :unprocessable_entity
      end

      test 'deletions from other teams never appear' do
        other = @other_team.issues.create!(title: 'x', lane: @other_lane, creator: @user)
        other.destroy!
        @other_team.projects.create!(name: 'OP').destroy!

        get api_v1_team_deleted_path(@team), headers: @headers

        assert_response :success
        assert_empty JSON.parse(response.body)
      end

      test 'team outside the user is 404' do
        stranger = Team.create!(workspace: @workspace, name: 'S', identifier: 'ADS')

        get api_v1_team_deleted_path(stranger), headers: @headers

        assert_response :not_found
      end

      test 'missing token is 401' do
        get api_v1_team_deleted_path(@team)

        assert_response :unauthorized
      end
    end
  end
end
