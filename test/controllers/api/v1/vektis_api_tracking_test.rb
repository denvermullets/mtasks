require 'test_helper'

module Api
  module V1
    # Coverage for the v1 API as a catalogued VEKTIS surface — which, transitively, is coverage for
    # the MCP server: mtasks-mcp funnels all of its tools through one `apiRequest` against these
    # same routes with the same bearer token, so there is nothing else to instrument or to test.
    #
    # Two things this file exists to guarantee, beyond "an event fires":
    #
    # 1. Every event carries source `api`. That field is the only thing separating agent traffic
    #    from a human clicking the same button, and the whole change is worthless without it.
    # 2. The feature_id/action vocabulary is IDENTICAL to the web's. VektisTrackingTest asserts the
    #    same pairs from the same gestures with source `server`; if the two files ever disagree
    #    about what a gesture is called, analysis silently splits one feature into two.
    class VektisApiTrackingTest < ActionDispatch::IntegrationTest
      include VektisEventTestHelper

      setup do
        @user = User.create!(name: 'Api Tracking User', email: 'vektis_api_tracking@example.com',
                             password: 'password')
        @workspace = Workspace.create!(name: 'Api Tracking Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'Api Tracking Team', identifier: 'ATK')
        @team.team_memberships.create!(user: @user)
        enable_vektis!(@team)

        @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
        @done = @team.lanes.create!(name: 'Done', position: 1)
        @project = @team.projects.create!(name: 'Api Tracking Project')
        @label = @team.labels.create!(name: 'bug', color: '#ff0000')
        @issue = @team.issues.create!(title: 'Tracked issue', lane: @backlog, creator: @user)

        @headers = api_headers_for(@user)
        clear_enqueued_jobs
      end

      # `pairs` includes the api-read event on every GET, so write assertions filter it out; the
      # read event has its own section below. One block parameter, not two: `pairs` is an array of
      # [feature_id, action] arrays, and destructuring it makes Style/HashExcept mistake it for a
      # Hash and suggest an `except` that would raise.
      def write_pairs
        pairs.reject { |pair| pair.first == 'api-read' }
      end

      # --- the source stamp ------------------------------------------------------------------

      test 'every API event is stamped source api and stays taxonomy conformant' do
        post api_v1_team_issues_path(@team),
             params: { issue: { title: 'From an agent', lane_id: @backlog.id } }.to_json,
             headers: @headers
        assert_response :created

        assert_predicate emitted, :any?
        emitted.each { |event| assert_taxonomy_conformant(event, source: 'api') }
      end

      test 'a call site cannot smuggle a different source through properties' do
        # The guarantee VektisTracking relies on, re-asserted from the surface that gained the
        # legitimate override: `source` is a named parameter, never a property.
        Vektis::EventEmitter.feature('issue-create', 'create', team: @team,
                                                               properties: { source: 'browser' }, source: 'api')

        assert_equal 'api', event_for('issue-create')['properties']['source']
      end

      test 'the API attributes events to the token owner and the path team' do
        post api_v1_team_issues_path(@team),
             params: { issue: { title: 'Attributed', lane_id: @backlog.id } }.to_json,
             headers: @headers

        assert_equal [@team.id], emitted_team_ids.uniq
        assert_equal @user.id.to_s, event_for('issue-create')['user_id']
        assert_equal VEKTIS_TEST_CUSTOMER_ID, event_for('issue-create')['customer_id']
      end

      # --- issues ------------------------------------------------------------------------------

      test 'creating an issue emits issue-create with shape properties only' do
        post api_v1_team_issues_path(@team),
             params: { issue: { title: 'Brand new', lane_id: @backlog.id, priority: 'high',
                                project_id: @project.id } }.to_json,
             headers: @headers

        assert_equal [%w[issue-create create]], write_pairs
        event = event_for('issue-create')
        assert_equal 'high', event['properties']['priority']
        assert event['properties']['has_project']
        assert_not event['properties']['is_sub_issue']
        assert_no_user_content('Brand new', 'Api Tracking Project')
      end

      test 'creating a sub-issue with labels emits one event per feature' do
        post api_v1_team_issues_path(@team),
             params: { issue: { title: 'Child', lane_id: @backlog.id,
                                parent_issue_id: @issue.id, label_ids: [@label.id] } }.to_json,
             headers: @headers

        assert_equal [%w[issue-create create], %w[sub-issue link], %w[issue-label apply]], write_pairs
        assert event_for('issue-create')['properties']['is_sub_issue']
        assert_equal 1, event_for('issue-label')['properties']['count']
      end

      test 'a lane-only PATCH emits exactly one issue-workflow event and no issue-edit' do
        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { lane_id: @done.id } }.to_json, headers: @headers

        assert_equal [%w[issue-workflow complete]], write_pairs
        event = event_for('issue-workflow')
        assert_equal 0, event['properties']['from_position']
        assert_equal 1, event['properties']['to_position']
        assert_equal 'forward', event['properties']['direction']
      end

      test 'a PATCH that edits fields and moves a lane emits both features once each' do
        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { title: 'Renamed', priority: 'urgent', lane_id: @done.id } }.to_json,
              headers: @headers

        assert_equal [%w[issue-workflow complete], %w[issue-edit update]], write_pairs
        assert_no_user_content('Renamed')
      end

      test 'a PATCH that changes nothing trackable emits no write events' do
        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { title: @issue.title } }.to_json, headers: @headers

        assert_empty write_pairs
      end

      test 'label changes through the issue PATCH emit apply and remove with counts' do
        @issue.labels << @label
        other = @team.labels.create!(name: 'chore', color: '#00ff00')
        clear_enqueued_jobs

        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { label_ids: [other.id] } }.to_json, headers: @headers

        assert_equal [%w[issue-label apply], %w[issue-label remove]], write_pairs
        assert_equal 1, event_for('issue-label', 'apply')['properties']['count']
        assert_equal 1, event_for('issue-label', 'remove')['properties']['count']
      end

      test 'reparenting through the API emits sub-issue link then unlink' do
        parent = @team.issues.create!(title: 'Parent', lane: @backlog, creator: @user)

        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { parent_issue_id: parent.id } }.to_json, headers: @headers
        assert_equal [%w[sub-issue link]], write_pairs

        clear_enqueued_jobs
        patch api_v1_team_issue_path(@team, @issue),
              params: { issue: { parent_issue_id: nil } }.to_json, headers: @headers
        assert_equal [%w[sub-issue unlink]], write_pairs
      end

      test 'a rejected write emits nothing' do
        post api_v1_team_issues_path(@team),
             params: { issue: { title: '' } }.to_json, headers: @headers

        assert_response :unprocessable_entity
        assert_empty write_pairs
      end

      # --- projects, labels, comments, decisions, dependencies ---------------------------------

      test 'project CRUD emits project-management create update delete' do
        post api_v1_team_projects_path(@team),
             params: { project: { name: 'Created' } }.to_json, headers: @headers
        assert_equal [%w[project-management create]], write_pairs

        clear_enqueued_jobs
        patch api_v1_team_project_path(@team, @project),
              params: { project: { name: 'Renamed' } }.to_json, headers: @headers
        assert_equal [%w[project-management update]], write_pairs

        clear_enqueued_jobs
        delete api_v1_team_project_path(@team, @project), headers: @headers
        assert_equal [%w[project-management delete]], write_pairs
        assert_no_user_content('Created', 'Renamed')
      end

      test 'creating a label emits label-management create without the name' do
        post api_v1_team_labels_path(@team),
             params: { label: { name: 'regression', color: '#123456' } }.to_json, headers: @headers

        assert_equal [%w[label-management create]], write_pairs
        assert_no_user_content('regression', '#123456')
      end

      test 'commenting on an issue emits comment create with entity and depth' do
        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: 'a secret note' } }.to_json, headers: @headers

        assert_equal [%w[comment create]], write_pairs
        event = event_for('comment')
        assert_equal 'issue', event['properties']['entity']
        assert_equal 0, event['properties']['depth']
        assert_no_user_content('a secret note')
      end

      test 'commenting on a project reports entity project' do
        post api_v1_team_project_comments_path(@team, @project),
             params: { comment: { body: 'project note' } }.to_json, headers: @headers

        assert_equal [%w[comment create]], write_pairs
        assert_equal 'project', event_for('comment')['properties']['entity']
      end

      test 'an idempotent comment replay emits nothing the second time' do
        headers = @headers.merge('Idempotency-Key' => 'hourglass-message-1')

        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: 'first delivery' } }.to_json, headers: headers
        assert_response :created
        assert_equal [%w[comment create]], write_pairs

        clear_enqueued_jobs
        post api_v1_team_issue_comments_path(@team, @issue),
             params: { comment: { body: 'first delivery' } }.to_json, headers: headers
        assert_response :success
        assert_empty write_pairs, 'a redelivery is not new activity'
      end

      test 'issue dependencies emit link and unlink with a direction' do
        target = @team.issues.create!(title: 'Blocker', lane: @backlog, creator: @user)

        post api_v1_team_issue_issue_dependencies_path(@team, @issue),
             params: { target_issue_id: target.id, direction: 'blocked_by' }.to_json, headers: @headers
        assert_equal [%w[issue-dependency link]], write_pairs
        assert_equal 'blocked_by', event_for('issue-dependency')['properties']['direction']
        assert_equal 1, event_for('issue-dependency')['properties']['count']

        dependency_id = response.parsed_body['id']
        clear_enqueued_jobs
        delete api_v1_team_issue_issue_dependency_path(@team, @issue, dependency_id), headers: @headers
        assert_equal [%w[issue-dependency unlink]], write_pairs
        assert_equal 'blocked_by', event_for('issue-dependency')['properties']['direction']
      end

      test 'pinning and unpinning a decision emits decision create and delete' do
        post api_v1_team_issue_decisions_path(@team, @issue),
             params: { hourglass_message_id: 'msg-1', body_snapshot: 'we ship on friday' }.to_json,
             headers: @headers
        assert_response :created
        assert_equal [%w[decision create]], write_pairs
        assert_equal 'issue', event_for('decision')['properties']['entity']
        assert_no_user_content('we ship on friday')

        decision_id = response.parsed_body['id']
        clear_enqueued_jobs
        delete api_v1_team_issue_decision_path(@team, @issue, decision_id), headers: @headers
        assert_equal [%w[decision delete]], write_pairs
      end

      test 'a replayed decision emits nothing the second time' do
        headers = @headers.merge('Idempotency-Key' => 'decision-key-1')
        params = { hourglass_message_id: 'msg-2', body_snapshot: 'decided' }.to_json

        post api_v1_team_issue_decisions_path(@team, @issue), params: params, headers: headers
        assert_equal [%w[decision create]], write_pairs

        clear_enqueued_jobs
        post api_v1_team_issue_decisions_path(@team, @issue), params: params, headers: headers
        assert_empty write_pairs
      end

      # --- reads -------------------------------------------------------------------------------

      test 'a collection GET emits api-read with the entity and a result count' do
        get api_v1_team_issues_path(@team), headers: @headers

        assert_equal [%w[api-read query]], pairs
        event = event_for('api-read')
        assert_equal 'issue', event['properties']['entity']
        assert_equal 1, event['properties']['result_count']
        assert_equal 'api', event['properties']['source']
      end

      test 'a single-record GET emits api-read with no result_count' do
        get api_v1_team_issue_path(@team, @issue), headers: @headers

        assert_equal [%w[api-read query]], pairs
        assert_not_includes event_for('api-read')['properties'].keys, 'result_count'
      end

      test 'by_identifier resolves its own tenant so the read is attributed' do
        get "/api/v1/issues/by_identifier/#{@issue.identifier}", headers: @headers

        assert_equal [%w[api-read query]], pairs
        assert_equal [@team.id], emitted_team_ids
      end

      test 'each collection endpoint reports its own entity' do
        {
          api_v1_team_projects_path(@team) => 'project',
          api_v1_team_lanes_path(@team) => 'lane',
          api_v1_team_labels_path(@team) => 'label',
          api_v1_team_members_path(@team) => 'member',
          api_v1_team_issue_comments_path(@team, @issue) => 'comment',
          api_v1_team_issue_issue_dependencies_path(@team, @issue) => 'issue_dependency'
        }.each do |path, entity|
          clear_enqueued_jobs
          get path, headers: @headers

          assert_equal [%w[api-read query]], pairs, "#{path} should emit one read event"
          assert_equal entity, event_for('api-read')['properties']['entity']
          assert_kind_of Integer, event_for('api-read')['properties']['result_count']
        end
      end

      test 'a failed GET emits nothing' do
        get api_v1_team_issue_path(@team, 0), headers: @headers

        assert_response :not_found
        assert_empty pairs
      end

      test 'endpoints with no single tenant emit nothing' do
        # users#me and teams#index span every team the token can see; guessing one would file
        # another tenant's activity under it, so absence here is the correct answer.
        get api_v1_me_path, headers: @headers
        assert_response :success
        assert_empty pairs

        get api_v1_teams_path, headers: @headers
        assert_response :success
        assert_empty pairs
      end

      test 'an unauthenticated request emits nothing' do
        get api_v1_team_issues_path(@team), headers: { 'Authorization' => 'Bearer nope' }

        assert_response :unauthorized
        assert_empty pairs
      end

      test 'a team with vektis disconnected emits nothing' do
        disable_vektis!(@team)

        post api_v1_team_issues_path(@team),
             params: { issue: { title: 'Silent', lane_id: @backlog.id } }.to_json, headers: @headers

        assert_response :created
        assert_empty emitted
      end
    end
  end
end
