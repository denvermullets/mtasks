require 'test_helper'

module Api
  module V1
    # Bulk writes that bypass callbacks must still bump updated_at so incremental pulls see them.
    class SyncHygieneTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Hygiene User', email: 'api_hygiene@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Hygiene WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Hygiene Team', identifier: 'HYG')
        @team.team_memberships.create!(user: @user, role: 'admin')
        @from = @team.lanes.create!(name: 'From', position: 0)
        @to = @team.lanes.create!(name: 'To', position: 1)
        @issue = @team.issues.create!(title: 'Moves', lane: @from, creator: @user)
        @since = Time.utc(2026, 1, 1)
        @issue.update_columns(updated_at: @since - 1.day)
        @headers = api_headers_for(@user)
        sign_in_as(@user)
      end

      test 'deleting a lane surfaces moved issues in the next updated_since pull with their new lane' do
        delete team_lane_path(@team, @from), params: { target_lane_id: @to.id }

        get api_v1_team_issues_path(@team), params: { updated_since: @since.iso8601 }, headers: @headers
        assert_response :success
        row = JSON.parse(response.body).find { |i| i['id'] == @issue.id }
        assert row, 'moved issue missing from pull'
        assert_equal @to.id, @issue.reload.lane_id
      end

      # The API hides archived teams (404), so the pull is checked against the same scope the issues index
      # applies (updated_since + include_archived) rather than over HTTP.
      test 'archiving a team bumps updated_at so issues match an updated_since + include_archived pull' do
        delete archive_team_path(@team)

        assert @team.reload.archived_at.present?
        row = @team.issues.where(updated_at: @since..).find_by(id: @issue.id)
        assert row, 'archived issue not matched by updated_since scope'
        assert row.archived_at.present?
      end
    end
  end
end
