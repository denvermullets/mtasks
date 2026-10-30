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

      private

      def create_recurring(team, **attrs)
        RecurringIssue.create!({ team: team, creator: @user, title: 'R', frequency: :daily,
                                 next_run_on: Date.current }.merge(attrs))
      end
    end
  end
end
