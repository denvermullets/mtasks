require 'test_helper'

module Api
  module V1
    class ActivityControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_activity@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'APA')
        @team.team_memberships.create!(user: @user)
        @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
        @doing = @team.lanes.create!(name: 'Doing', position: 1)
        @issue = @team.issues.create!(title: 'Original', lane: @backlog, creator: @user)
        @headers = api_headers_for(@user)
      end

      test 'returns unauthorized without token' do
        get api_v1_team_issue_activity_path(@team, @issue), headers: { 'Content-Type' => 'application/json' }
        assert_response :unauthorized
      end

      test 'returns field changes with resolved names' do
        PaperTrail.request(whodunnit: @user.id.to_s) do
          @issue.update!(title: 'Renamed', lane: @doing, assignee: @user, priority: :high)
        end

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        assert_response :success
        body = response.parsed_body
        assert_equal 1, body.size
        entry = body.first
        assert_equal 'version', entry['type']
        assert_equal 'update', entry['event']
        assert_equal({ 'id' => @user.id, 'name' => 'API User' }, entry['actor'])

        by_field = entry['changes'].index_by { |c| c['field'] }
        assert_equal({ 'from' => 'Original', 'to' => 'Renamed' }, by_field['title'].slice('from', 'to'))
        assert_equal({ 'id' => @backlog.id, 'name' => 'Backlog' }, by_field['lane_id']['from'])
        assert_equal({ 'id' => @doing.id, 'name' => 'Doing' }, by_field['lane_id']['to'])
        assert_nil by_field['assignee_id']['from']
        assert_equal({ 'id' => @user.id, 'name' => 'API User' }, by_field['assignee_id']['to'])
        assert_equal 'high', by_field['priority']['to']
      end

      test 'description matches what the web shows' do
        @issue.update!(lane: @doing)
        version = @issue.versions.where(event: 'update').last

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        assert_equal VersionDescriptionService.call(version), response.parsed_body.first['description']
        assert_includes response.parsed_body.first['description'], 'Doing'
      end

      test 'entries are ordered oldest first' do
        @issue.update!(title: 'One')
        @issue.update!(title: 'Two')

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        ids = response.parsed_body.pluck('id')
        assert_equal ids.sort, ids
        assert_equal 2, ids.size
      end

      test 'returns not found for a team outside the token' do
        other = User.create!(name: 'Other', email: 'other_activity@example.com', password: 'password')
        ws = Workspace.create!(name: 'Other WS', owner: other)
        team = ws.teams.create!(name: 'Other', identifier: 'OTA')
        lane = team.lanes.create!(name: 'Backlog', position: 0)
        issue = team.issues.create!(title: 'Theirs', lane: lane, creator: other)

        get api_v1_team_issue_activity_path(team, issue), headers: @headers
        assert_response :not_found
      end

      test 'returns not found for an issue from another team' do
        other_team = @workspace.teams.create!(name: 'Second', identifier: 'APB')
        other_team.team_memberships.create!(user: @user)
        lane = other_team.lanes.create!(name: 'Backlog', position: 0)
        issue = other_team.issues.create!(title: 'Elsewhere', lane: lane, creator: @user)

        get api_v1_team_issue_activity_path(@team, issue), headers: @headers
        assert_response :not_found
      end
    end
  end
end
