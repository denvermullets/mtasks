require 'test_helper'

module Api
  module V1
    class ProjectActivityControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_pactivity@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'APJ')
        @team.team_memberships.create!(user: @user)
        @project = @team.projects.create!(name: 'Original')
        @headers = api_headers_for(@user)
      end

      test 'returns unauthorized without token' do
        get api_v1_team_project_activity_path(@team, @project), headers: { 'Content-Type' => 'application/json' }
        assert_response :unauthorized
      end

      test 'name, status and lead changes produce a version entry with structured changes' do
        PaperTrail.request(whodunnit: @user.id.to_s) do
          @project.update!(name: 'Renamed', status: 'started', lead: @user)
        end

        get api_v1_team_project_activity_path(@team, @project), headers: @headers
        assert_response :success
        body = response.parsed_body
        assert_equal 1, body.size
        entry = body.first
        assert_equal 'version', entry['type']
        assert_equal 'update', entry['event']
        assert_equal @user.id, entry['actor']['id']
        assert entry['cursor'].present?
        assert entry['description'].present?

        by_field = entry['changes'].index_by { |c| c['field'] }
        assert_equal({ 'from' => 'Original', 'to' => 'Renamed' }, by_field['name'].slice('from', 'to'))
        assert_equal({ 'from' => 'backlog', 'to' => 'started' }, by_field['status'].slice('from', 'to'))
        assert_nil by_field['lead_id']['from']
        assert_equal({ 'id' => @user.id, 'name' => 'API User' }, by_field['lead_id']['to'])
      end

      test 'priority, dates, description and roadmap commitment are tracked' do
        @project.update!(priority: :high, start_date: Date.new(2026, 1, 1), due_date: Date.new(2026, 2, 1),
                         roadmap_commitment: 'now', description: 'x')

        get api_v1_team_project_activity_path(@team, @project), headers: @headers
        fields = response.parsed_body.first['changes'].pluck('field')
        assert_equal %w[description due_date priority roadmap_commitment start_date], fields.sort
      end

      test 'untracked columns do not create versions' do
        @project.update!(velocity_score: 3, total_issues_count: 4)
        @project.recalculate_velocity!

        get api_v1_team_project_activity_path(@team, @project), headers: @headers
        assert_empty response.parsed_body
      end

      test 'creation is not an activity entry' do
        get api_v1_team_project_activity_path(@team, @project), headers: @headers
        assert_empty response.parsed_body
      end

      test 'deleting a project still appears in the team deleted feed' do
        @project.update!(name: 'Changed')
        id = @project.id
        @project.destroy!

        get api_v1_team_deleted_path(@team), headers: @headers
        assert_response :success
        assert_equal([{ 'record_type' => 'Project', 'record_id' => id }],
                     response.parsed_body.map { |e| e.slice('record_type', 'record_id') })
      end

      test 'entries are oldest first and page with limit and before_id' do
        3.times { |i| @project.update!(name: "N#{i}") }

        get api_v1_team_project_activity_path(@team, @project), headers: @headers
        full = response.parsed_body.pluck('cursor')
        assert_equal 3, full.size
        ids = response.parsed_body.pluck('id')
        assert_equal ids.sort, ids

        paged = []
        before = nil
        loop do
          params = { limit: 2 }
          params[:before_id] = before if before
          get api_v1_team_project_activity_path(@team, @project), params: params, headers: @headers
          paged.unshift(*response.parsed_body.pluck('cursor'))
          before = response.headers['X-Next-Before-Id']
          break unless before
        end
        assert_equal full, paged
      end

      test 'since returns only newer entries' do
        travel_to 2.days.ago do
          @project.update!(name: 'Old')
        end
        @project.update!(name: 'New')

        get api_v1_team_project_activity_path(@team, @project),
            params: { since: 1.day.ago.iso8601 }, headers: @headers
        assert_equal 1, response.parsed_body.size
      end

      test 'unknown before_id is not found' do
        get api_v1_team_project_activity_path(@team, @project), params: { before_id: '0' }, headers: @headers
        assert_response :not_found
      end

      test 'returns not found for a team outside the token' do
        other = User.create!(name: 'Other', email: 'other_pactivity@example.com', password: 'password')
        team = Workspace.create!(name: 'Other WS', owner: other).teams.create!(name: 'Other', identifier: 'OTJ')
        project = team.projects.create!(name: 'Theirs')

        get api_v1_team_project_activity_path(team, project), headers: @headers
        assert_response :not_found
      end

      test 'returns not found for a project from another team' do
        other_team = @workspace.teams.create!(name: 'Second', identifier: 'APK')
        other_team.team_memberships.create!(user: @user)
        project = other_team.projects.create!(name: 'Elsewhere')

        get api_v1_team_project_activity_path(@team, project), headers: @headers
        assert_response :not_found
      end
    end
  end
end
