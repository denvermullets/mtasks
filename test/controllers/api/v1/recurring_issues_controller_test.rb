require 'test_helper'

module Api
  module V1
    class RecurringIssuesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_recurring@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'ARC')
        @team.team_memberships.create!(user: @user)
        @headers = api_headers_for(@user)

        @recurring = create_recurring(@team, title: 'Deploy', frequency: :weekly, weekday: 3)
      end

      test 'lists recurring issues with schedule fields and summary' do
        get api_v1_team_recurring_issues_path(@team), headers: @headers

        assert_response :success
        assert response.headers['X-Server-Time'].present?
        json = JSON.parse(response.body)
        assert_equal 1, json.length
        row = json.first
        assert_equal 'Deploy', row['title']
        assert_equal 'weekly', row['frequency']
        assert_equal 3, row['weekday']
        assert_equal 'Every week on Wednesday', row['schedule_summary']
        assert_equal @user.id, row['creator']['id']
        assert_equal [], row['label_ids']
        assert_equal true, row['active']
      end

      test 'updated_since filters' do
        old = create_recurring(@team, title: 'Old')
        old.update_columns(updated_at: 2.days.ago)

        get api_v1_team_recurring_issues_path(@team), params: { updated_since: 1.day.ago.iso8601 }, headers: @headers

        assert_equal ['Deploy'], JSON.parse(response.body).pluck('title')
      end

      test 'never lists another team recurring issues' do
        other = @workspace.teams.create!(name: 'Other', identifier: 'OTH')
        other.team_memberships.create!(user: @user)
        create_recurring(other, title: 'Elsewhere')

        get api_v1_team_recurring_issues_path(@team), headers: @headers

        assert_equal ['Deploy'], JSON.parse(response.body).pluck('title')
      end

      test 'team outside the token is 404' do
        stranger = User.create!(name: 'S', email: 'stranger_rec@example.com', password: 'password')
        ws = Workspace.create!(name: 'Other WS', owner: stranger)
        foreign = ws.teams.create!(name: 'Foreign', identifier: 'FRN')
        foreign.team_memberships.create!(user: stranger)

        get api_v1_team_recurring_issues_path(foreign), headers: @headers

        assert_response :not_found
      end

      test 'create returns 201 with schedule summary and computed next run' do
        post api_v1_team_recurring_issues_path(@team), params: create_body(frequency: 'weekly', weekday: 1,
                                                                           starts_on: '2030-01-01'), headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'Every week on Monday', json['schedule_summary']
        assert_equal '2030-01-07', json['next_run_on']
        assert_equal @user.id, json['creator']['id']
        assert_equal 1, @team.recurring_issues.where(title: 'Standup').count
      end

      test 'create defaults time zone to the user time zone' do
        post api_v1_team_recurring_issues_path(@team), params: create_body, headers: @headers

        assert_response :created
        assert_equal @user.time_zone, JSON.parse(response.body)['time_zone']
      end

      test 'create honours an explicit time zone and label ids' do
        label = @team.labels.create!(name: 'ops', color: '#ff0000')
        post api_v1_team_recurring_issues_path(@team),
             params: create_body(time_zone: 'Tokyo', label_ids: [label.id]), headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'Tokyo', json['time_zone']
        assert_equal [label.id], json['label_ids']
      end

      test 'create rejects references from another team' do
        other = @workspace.teams.create!(name: 'Other', identifier: 'OTH')
        other.team_memberships.create!(user: @user)
        foreign = {
          lane_id: other.lanes.first&.id || other.lanes.create!(name: 'L', position: 1).id,
          project_id: other.projects.create!(name: 'P').id,
          assignee_id: User.create!(name: 'X', email: 'x_rec@example.com', password: 'password').id,
          label_ids: [other.labels.create!(name: 'l', color: '#000000').id]
        }
        foreign.each do |key, value|
          assert_no_difference 'RecurringIssue.count' do
            post api_v1_team_recurring_issues_path(@team), params: create_body(key => value), headers: @headers
          end
          assert_response :unprocessable_entity, key.to_s
        end
      end

      test 'create with invalid schedule is 422' do
        post api_v1_team_recurring_issues_path(@team), params: create_body(interval: 0), headers: @headers
        assert_response :unprocessable_entity

        post api_v1_team_recurring_issues_path(@team), params: create_body(starts_on: 'nope'), headers: @headers
        assert_response :unprocessable_entity
      end

      test 'create with a read-only token is 403' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
        post api_v1_team_recurring_issues_path(@team), params: create_body, headers: headers
        assert_response :forbidden
      end

      private

      def create_body(starts_on: '2030-01-01', **attrs)
        { recurring_issue: { title: 'Standup', frequency: 'daily', interval: 1, starts_on: starts_on }.merge(attrs) }
          .to_json
      end

      def create_recurring(team, **attrs)
        RecurringIssue.create!({ team: team, creator: @user, title: 'R', frequency: :daily,
                                 next_run_on: Date.current }.merge(attrs))
      end
    end
  end
end
