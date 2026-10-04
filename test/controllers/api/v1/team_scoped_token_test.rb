require 'test_helper'

module Api
  module V1
    # A token scoped to teams {A, B} must behave as if team C does not exist, on every entry point.
    class TeamScopedTokenTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Scope User', email: "scope_#{SecureRandom.hex(4)}@example.com",
                             password: 'password')
        @workspace = Workspace.create!(name: 'Scope WS', owner: @user)
        @team_a = build_team('Alpha', 'ALP')
        @team_b = build_team('Bravo', 'BRV')
        @team_c = build_team('Charlie', 'CHR')

        @issue_c = @team_c.issues.create!(title: 'C issue', lane: @team_c.lanes.first, creator: @user)
        @project_c = @team_c.projects.create!(name: 'C project')
        @label_c = @team_c.labels.create!(name: 'C label', color: '#ff0000')

        @token = ApiToken.generate_for(@user, name: 'AB', teams: [@team_a, @team_b])
        @headers = headers_for(@token)
      end

      def build_team(name, identifier)
        team = @workspace.teams.create!(name: name, identifier: identifier)
        team.team_memberships.create!(user: @user)
        team
      end

      def headers_for(token)
        { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
      end

      test 'teams index lists only the scoped teams' do
        get api_v1_teams_path, headers: @headers

        assert_response :success
        assert_equal [@team_a.id, @team_b.id].sort, JSON.parse(response.body).pluck('id').sort
      end

      test 'unscoped token still lists every team' do
        get api_v1_teams_path, headers: headers_for(ApiToken.generate_for(@user, name: 'Wide'))

        assert_equal 3, JSON.parse(response.body).size
      end

      test 'scope changes apply to the same credential' do
        @token.add_team!(@team_c)
        get api_v1_team_projects_path(@team_c), headers: @headers
        assert_response :success

        @token.remove_team!(@team_c)
        get api_v1_team_projects_path(@team_c), headers: @headers
        assert_response :not_found
      end

      test 'every nested resource under an out-of-scope team is not found' do
        requests = [
          [:get, api_v1_team_issues_path(@team_c)],
          [:get, api_v1_team_issue_path(@team_c, @issue_c)],
          [:post, api_v1_team_issues_path(@team_c), { issue: { title: 'x' } }],
          [:get, api_v1_team_issue_comments_path(@team_c, @issue_c)],
          [:post, api_v1_team_issue_comments_path(@team_c, @issue_c), { comment: { body: 'x' } }],
          [:get, api_v1_team_issue_issue_dependencies_path(@team_c, @issue_c)],
          [:post, api_v1_team_issue_decisions_path(@team_c, @issue_c),
           { hourglass_message_id: 'm1', body_snapshot: 'x' }],
          [:get, api_v1_team_projects_path(@team_c)],
          [:get, api_v1_team_project_path(@team_c, @project_c)],
          [:get, api_v1_team_project_comments_path(@team_c, @project_c)],
          [:get, api_v1_team_lanes_path(@team_c)],
          [:get, api_v1_team_labels_path(@team_c)],
          [:get, api_v1_team_members_path(@team_c)]
        ]

        requests.each do |verb, path, body|
          send(verb, path, params: body&.to_json, headers: @headers)
          assert_response :not_found, "#{verb.upcase} #{path}"
        end
      end

      test 'by_identifier hides out-of-scope teams' do
        get "/api/v1/issues/by_identifier/#{@issue_c.identifier}", headers: @headers
        assert_response :not_found
      end

      test 'by_email only finds users in scoped teams' do
        outsider = User.create!(name: 'C only', email: "c_only_#{SecureRandom.hex(4)}@example.com",
                                password: 'password')
        @team_c.team_memberships.create!(user: outsider)

        get api_v1_users_by_email_path(email: outsider.email), headers: @headers
        assert_response :not_found
      end

      test 'issue writes reject references into another team' do
        post api_v1_team_issues_path(@team_a),
             params: { issue: { title: 'x', lane_id: @team_a.lanes.first.id,
                                project_id: @project_c.id, label_ids: [@label_c.id] } }.to_json,
             headers: @headers

        assert_response :unprocessable_entity
        errors = JSON.parse(response.body)['errors'].join
        assert_includes errors, 'project_id'
        assert_includes errors, 'label_ids'
        assert_equal 0, @team_a.issues.count
      end

      test 'issue update rejects a label from another team before writing it' do
        issue = @team_a.issues.create!(title: 'A issue', lane: @team_a.lanes.first, creator: @user)

        patch api_v1_team_issue_path(@team_a, issue),
              params: { issue: { label_ids: [@label_c.id] } }.to_json, headers: @headers

        assert_response :unprocessable_entity
        assert_empty issue.reload.labels
      end

      test 'project writes reject a lead outside the team' do
        outsider = User.create!(name: 'Lead', email: "lead_#{SecureRandom.hex(4)}@example.com", password: 'password')

        post api_v1_team_projects_path(@team_a),
             params: { project: { name: 'P', lead_id: outsider.id } }.to_json, headers: @headers

        assert_response :unprocessable_entity
      end
    end
  end
end
