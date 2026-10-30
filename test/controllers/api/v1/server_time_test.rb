require 'test_helper'

module Api
  module V1
    # Every endpoint that takes a time cursor shares one parser: bad input is a 422 with the same
    # message shape, and X-Server-Time goes out on every response, 422s included.
    class ServerTimeTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Clock User', email: 'api_clock@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Clock WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Clock Team', identifier: 'CLK')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'Backlog', position: 0)
        @issue = @team.issues.create!(title: 'Clocked', lane: @lane, creator: @user)
        @project = @team.projects.create!(name: 'Clocked project')
        @headers = api_headers_for(@user)
      end

      def endpoints
        {
          api_v1_team_issues_path(@team) => 'updated_since',
          api_v1_team_projects_path(@team) => 'updated_since',
          api_v1_team_comments_path(@team) => 'updated_since',
          api_v1_saved_views_path => 'updated_since',
          api_v1_team_recurring_issues_path(@team) => 'updated_since',
          api_v1_team_deleted_path(@team) => 'since',
          api_v1_deleted_path => 'since',
          api_v1_team_project_activity_path(@team, @project) => 'since',
          api_v1_team_issue_activity_path(@team, @issue) => 'since',
          api_v1_notifications_path => 'updated_since'
        }
      end

      test 'every time-cursor endpoint sends X-Server-Time on success' do
        endpoints.each_key do |path|
          get path, headers: @headers

          assert_response :success, path
          assert Time.iso8601(response.headers['X-Server-Time']), "#{path} missing X-Server-Time"
        end
      end

      test 'every time-cursor endpoint rejects a bad value with the same 422 and still sends X-Server-Time' do
        endpoints.each do |path, param|
          get path, params: { param => 'yesterday' }, headers: @headers

          assert_response :unprocessable_entity, path
          assert_equal ["#{param} must be an ISO8601 timestamp"], response.parsed_body['errors'], path
          assert Time.iso8601(response.headers['X-Server-Time']), "#{path} 422 missing X-Server-Time"
        end
      end

      test 'a valid cursor is accepted everywhere' do
        endpoints.each do |path, param|
          get path, params: { param => 1.hour.ago.utc.iso8601 }, headers: @headers

          assert_response :success, path
        end
      end

      test 'notifications keeps server_time in the body and also sends the header' do
        get api_v1_notifications_path, headers: @headers

        assert response.parsed_body.dig('meta', 'server_time').present?
        assert response.headers['X-Server-Time'].present?
      end
    end
  end
end
