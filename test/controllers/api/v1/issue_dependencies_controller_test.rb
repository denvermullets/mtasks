require 'test_helper'

module Api
  module V1
    class IssueDependenciesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_deps@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'APD')
        @team.team_memberships.create!(user: @user)

        @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
        @issue_a = @team.issues.create!(title: 'Issue A', lane: @backlog, creator: @user)
        @issue_b = @team.issues.create!(title: 'Issue B', lane: @backlog, creator: @user)
        @headers = api_headers_for(@user)
      end

      # Create - blocking direction
      test 'creates blocking dependency' do
        assert_difference 'IssueDependency.count', 1 do
          post api_v1_team_issue_issue_dependencies_path(@team, @issue_a),
               params: { target_issue_id: @issue_b.id, direction: 'blocking' }.to_json,
               headers: @headers
        end

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal @issue_a.id, json['blocking_issue']['id']
        assert_equal @issue_b.id, json['blocked_issue']['id']
      end

      # Create - blocked_by direction
      test 'creates blocked_by dependency' do
        post api_v1_team_issue_issue_dependencies_path(@team, @issue_a),
             params: { target_issue_id: @issue_b.id, direction: 'blocked_by' }.to_json,
             headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal @issue_b.id, json['blocking_issue']['id']
        assert_equal @issue_a.id, json['blocked_issue']['id']
      end

      # Create - self-block
      test 'returns error when blocking self' do
        post api_v1_team_issue_issue_dependencies_path(@team, @issue_a),
             params: { target_issue_id: @issue_a.id, direction: 'blocking' }.to_json,
             headers: @headers

        assert_response :unprocessable_entity
      end

      # Create - target not found
      test 'returns not found for missing target issue' do
        post api_v1_team_issue_issue_dependencies_path(@team, @issue_a),
             params: { target_issue_id: 999_999, direction: 'blocking' }.to_json,
             headers: @headers

        assert_response :not_found
      end

      # Index
      test 'lists dependencies for an issue with direction relative to it' do
        blocking = IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
        blocked_by = IssueDependency.create!(blocking_issue: @issue_b, blocked_issue: @issue_a)

        get api_v1_team_issue_issue_dependencies_path(@team, @issue_a), headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 2, json.length

        by_id = json.index_by { |d| d['id'] }
        assert_equal 'blocking', by_id[blocking.id]['direction']
        assert_equal 'blocked_by', by_id[blocked_by.id]['direction']
        assert_equal @issue_b.id, by_id[blocking.id]['blocked_issue']['id']
      end

      test 'index returns empty array when issue has no dependencies' do
        get api_v1_team_issue_issue_dependencies_path(@team, @issue_a), headers: @headers

        assert_response :success
        assert_equal [], JSON.parse(response.body)
      end

      # Destroy
      test 'destroys dependency' do
        dep = IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)

        assert_difference 'IssueDependency.count', -1 do
          delete api_v1_team_issue_issue_dependency_path(@team, @issue_a, dep), headers: @headers
        end

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal true, json['ok']
        assert_equal dep.id, json['id']
      end

      test 'returns not found for non-existent dependency' do
        delete api_v1_team_issue_issue_dependency_path(@team, @issue_a, 999_999), headers: @headers
        assert_response :not_found
      end

      # Issue show includes dependencies
      test 'issue show includes blocking and blocked issues' do
        IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)

        get api_v1_team_issue_path(@team, @issue_a), headers: @headers

        json = JSON.parse(response.body)
        assert_equal 1, json['blocked_issues'].length
        assert_equal @issue_b.id, json['blocked_issues'].first['id']
        assert_equal 0, json['blocking_issues'].length
      end

      # Issue show exposes the dependency record id so it can be removed
      test 'issue show includes dependency_id on dependency entries' do
        dep = IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)

        get api_v1_team_issue_path(@team, @issue_a), headers: @headers

        json = JSON.parse(response.body)
        assert_equal dep.id, json['blocked_issues'].first['dependency_id']
      end
    end
  end
end
