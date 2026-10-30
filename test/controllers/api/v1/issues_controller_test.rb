require 'test_helper'

module Api
  module V1
    class IssuesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_issues@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'APT')
        @team.team_memberships.create!(user: @user)

        @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
        @done = @team.lanes.create!(name: 'Done', position: 1, category: 'completed')

        @issue = @team.issues.create!(title: 'Existing issue', lane: @backlog, creator: @user)
        @headers = api_headers_for(@user)
      end

      # Authentication
      test 'returns unauthorized without token' do
        get api_v1_team_issues_path(@team), headers: { 'Content-Type' => 'application/json' }
        assert_response :unauthorized
      end

      # Team scoping
      test 'returns not found for non-member team' do
        other_user = User.create!(name: 'Other', email: 'other_issues@example.com', password: 'password')
        other_workspace = Workspace.create!(name: 'Other WS', owner: other_user)
        other_team = other_workspace.teams.create!(name: 'Other', identifier: 'OTR')

        get api_v1_team_issues_path(other_team), headers: @headers
        assert_response :not_found
      end

      # Index: incremental pull
      test 'index sends X-Server-Time' do
        get api_v1_team_issues_path(@team), headers: @headers

        assert_response :success
        assert Time.iso8601(response.headers['X-Server-Time'])
      end

      test 'updated_since returns issues at or after the time, oldest first, ties by id' do
        t = Time.utc(2026, 1, 1, 12)
        old = @team.issues.create!(title: 'Old', lane: @backlog, creator: @user)
        a = @team.issues.create!(title: 'A', lane: @backlog, creator: @user)
        b = @team.issues.create!(title: 'B', lane: @backlog, creator: @user)
        c = @team.issues.create!(title: 'C', lane: @backlog, creator: @user)
        @issue.update_columns(updated_at: t - 1.day)
        old.update_columns(updated_at: t - 1.second)
        c.update_columns(updated_at: t + 1.minute)
        a.update_columns(updated_at: t)
        b.update_columns(updated_at: t)

        get api_v1_team_issues_path(@team), params: { updated_since: t.iso8601 }, headers: @headers

        assert_response :success
        assert_equal [a.id, b.id, c.id], JSON.parse(response.body).pluck('id')
        assert response.headers['X-Server-Time'].present?
      end

      test 'invalid updated_since returns 422 with X-Server-Time' do
        get api_v1_team_issues_path(@team), params: { updated_since: 'yesterday' }, headers: @headers

        assert_response :unprocessable_entity
        body = JSON.parse(response.body)
        assert_equal 'Unprocessable Entity', body['error']
        assert body['errors'].any?
      end

      # updated_at hygiene
      test 'adding a label via update makes the issue appear in the next updated_since pull' do
        label = @team.labels.create!(name: 'Bug', color: '#ff0000')
        @issue.update_columns(updated_at: 1.day.ago)
        cursor = 1.hour.ago

        patch api_v1_team_issue_path(@team, @issue), params: { issue: { label_ids: [label.id] } },
                                                     headers: @headers, as: :json
        assert_response :success

        get api_v1_team_issues_path(@team), params: { updated_since: cursor.utc.iso8601 }, headers: @headers
        assert_includes JSON.parse(response.body).pluck('id'), @issue.id
      end

      test 'removing a label via update makes the issue appear in the next updated_since pull' do
        label = @team.labels.create!(name: 'Bug', color: '#ff0000')
        @issue.labels << label
        @issue.update_columns(updated_at: 1.day.ago)
        cursor = 1.hour.ago

        patch api_v1_team_issue_path(@team, @issue), params: { issue: { label_ids: [] } },
                                                     headers: @headers, as: :json
        assert_response :success

        get api_v1_team_issues_path(@team), params: { updated_since: cursor.utc.iso8601 }, headers: @headers
        assert_includes JSON.parse(response.body).pluck('id'), @issue.id
      end

      # Index
      test 'lists issues' do
        get api_v1_team_issues_path(@team), headers: @headers

        assert_response :success
        issues = JSON.parse(response.body)
        assert_equal 1, issues.length
        assert_equal 'Existing issue', issues.first['title']
        assert_equal @issue.identifier, issues.first['identifier']
      end

      test 'filters issues by lane' do
        @team.issues.create!(title: 'Done issue', lane: @done, creator: @user)

        get api_v1_team_issues_path(@team), params: { lane_id: @backlog.id }, headers: @headers

        issues = JSON.parse(response.body)
        assert_equal 1, issues.length
        assert_equal 'Existing issue', issues.first['title']
      end

      test 'filters issues by assignee' do
        other_user = User.create!(name: 'Assignee', email: 'assignee@example.com', password: 'password')
        @team.team_memberships.create!(user: other_user)
        @team.issues.create!(title: 'Assigned', lane: @backlog, creator: @user, assignee: other_user)

        get api_v1_team_issues_path(@team), params: { assignee_id: other_user.id }, headers: @headers

        issues = JSON.parse(response.body)
        assert_equal 1, issues.length
        assert_equal 'Assigned', issues.first['title']
      end

      test 'filters issues by priority' do
        @team.issues.create!(title: 'Urgent', lane: @backlog, creator: @user, priority: :urgent)

        get api_v1_team_issues_path(@team), params: { priority: 'urgent' }, headers: @headers

        issues = JSON.parse(response.body)
        assert_equal 1, issues.length
        assert_equal 'Urgent', issues.first['title']
      end

      # Show
      test 'shows issue with details' do
        get api_v1_team_issue_path(@team, @issue), headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal @issue.id, json['id']
        assert_equal 'Existing issue', json['title']
        assert json.key?('description')
      end

      test 'returns not found for non-existent issue' do
        get api_v1_team_issue_path(@team, 999_999), headers: @headers
        assert_response :not_found
      end

      # Create
      test 'creates issue with required params' do
        assert_difference 'Issue.count', 1 do
          post api_v1_team_issues_path(@team),
               params: { issue: { title: 'New issue', lane_id: @backlog.id } }.to_json,
               headers: @headers
        end

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'New issue', json['title']
        assert_equal @user.id, json['creator']['id']
      end

      test 'creates issue with priority and assignee' do
        post api_v1_team_issues_path(@team),
             params: { issue: { title: 'Urgent task', lane_id: @backlog.id, priority: 'high',
                                assignee_id: @user.id } }.to_json,
             headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'high', json['priority']
        assert_equal @user.id, json['assignee']['id']
      end

      test 'returns validation errors for invalid issue' do
        post api_v1_team_issues_path(@team),
             params: { issue: { title: '', lane_id: @backlog.id } }.to_json,
             headers: @headers

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert(json['errors'].any? { |e| e.include?('Title') })
      end

      # Update
      test 'updates issue' do
        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { title: 'Updated title' } }.to_json,
              headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 'Updated title', json['title']
      end

      test 'sets completed_at when moving to Done lane' do
        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { lane_id: @done.id } }.to_json,
              headers: @headers

        assert_response :success
        @issue.reload
        assert_not_nil @issue.completed_at
      end

      test 'clears completed_at when moving out of Done lane' do
        @issue.update!(lane: @done, completed_at: 1.hour.ago)

        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { lane_id: @backlog.id } }.to_json,
              headers: @headers

        @issue.reload
        assert_nil @issue.completed_at
      end
    end
  end
end
