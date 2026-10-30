require 'test_helper'

module Api
  module V1
    # Bulk writes that bypass callbacks must still bump updated_at so incremental pulls see them.
    class SyncHygieneTest < ActionDispatch::IntegrationTest
      def assert_pull_includes(path, record)
        get path, params: { updated_since: @since.iso8601 }, headers: @headers
        assert_response :success
        assert_includes response.parsed_body.pluck('id'), record.id, 'record missing from updated_since pull'
      end

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

      test 'deleting a comment surfaces the issue in the next updated_since pull' do
        comment = @issue.comments.create!(body: 'bye', user: @user)
        @issue.update_columns(updated_at: @since - 1.day)

        delete api_v1_team_issue_comment_path(@team, @issue, comment), headers: @headers

        assert_pull_includes api_v1_team_issues_path(@team), @issue
      end

      test 'removing a comment attachment surfaces the issue in the next updated_since pull' do
        comment = @issue.comments.create!(body: 'file', user: @user)
        comment.files.attach(io: StringIO.new('x'), filename: 'x.txt')
        @issue.update_columns(updated_at: @since - 1.day)

        delete api_v1_team_issue_comment_attachment_path(@team, @issue, comment, comment.files_attachments.first),
               headers: @headers

        assert_pull_includes api_v1_team_issues_path(@team), @issue
      end

      def dashboard_updated_at(dashboard)
        get api_v1_dashboards_path, headers: @headers
        Time.iso8601(response.parsed_body.find { |d| d['id'] == dashboard.id }['updated_at'])
      end

      test 'dashboard group move moves the dashboard updated_at seen by GET dashboards' do
        dashboard = @user.dashboards.create!(name: 'D', position: 1)
        a = dashboard.groups.create!(name: 'A', position: 1)
        dashboard.groups.create!(name: 'B', position: 2)
        dashboard.update_columns(updated_at: @since)

        patch move_api_v1_dashboard_group_path(dashboard, a), headers: @headers, params: { direction: 'down' }.to_json

        assert_response :ok
        assert_operator dashboard_updated_at(dashboard), :>, @since
      end

      test 'dashboard group reorder moves the dashboard updated_at seen by GET dashboards' do
        dashboard = @user.dashboards.create!(name: 'D', position: 1)
        a = dashboard.groups.create!(name: 'A', position: 1)
        b = dashboard.groups.create!(name: 'B', position: 2)
        dashboard.update_columns(updated_at: @since)

        patch reorder_api_v1_dashboard_groups_path(dashboard), headers: @headers,
                                                               params: { ids: [b.id, a.id] }.to_json

        assert_response :ok
        assert_operator dashboard_updated_at(dashboard), :>, @since
      end

      test 'editing only a group sources moves the dashboard updated_at seen by GET dashboards' do
        dashboard = @user.dashboards.create!(name: 'D', position: 1)
        group = dashboard.groups.create!(name: 'G', position: 1)
        group.replace_sources!(team_ids: [@team.id], project_ids: [])
        dashboard.update_columns(updated_at: @since)
        group.update_columns(updated_at: @since)

        patch api_v1_dashboard_group_path(dashboard, group), headers: @headers,
                                                             params: { dashboard_group: { team_ids: [] } }.to_json

        assert_response :ok
        assert_empty group.reload.sources
        assert_operator group.updated_at, :>, @since
        get api_v1_dashboards_path, headers: @headers
        row = response.parsed_body.find { |d| d['id'] == dashboard.id }
        assert_operator Time.iso8601(row['updated_at']), :>, @since
      end

      test 'recalculating project velocity moves updated_at only when the counts change' do
        project = @team.projects.create!(name: 'Counted')
        project.recalculate_velocity!
        project.update_columns(updated_at: @since)

        project.recalculate_velocity!
        assert_equal @since, project.reload.updated_at, 'unchanged counts should not bump updated_at'

        @issue.update_columns(project_id: project.id)
        project.recalculate_velocity!
        get api_v1_team_projects_path(@team), params: { updated_since: (@since + 1.minute).iso8601 }, headers: @headers
        row = response.parsed_body.find { |p| p['id'] == project.id }
        assert row, 'project with new counts missing from pull'
        assert_equal 1, row['total_issues_count']
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
