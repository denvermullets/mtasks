require 'test_helper'

module Api
  module V1
    class IssueHierarchiesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_hierarchy@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'AHT')
        @team.team_memberships.create!(user: @user)
        @backlog = @team.lanes.create!(name: 'Backlog', position: 0)

        @root = create_issue('Root')
        @child = create_issue('Child', parent: @root)
        @grandchild = create_issue('Grandchild', parent: @child)
        @headers = api_headers_for(@user)
      end

      test 'returns the nested tree from the top-level issue' do
        IssueDependency.create!(blocking_issue: @child, blocked_issue: @grandchild)

        get api_v1_team_issue_hierarchy_path(@team, @grandchild), headers: @headers

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal @grandchild.id, body['issue_id']
        assert_equal @root.id, body['root_id']
        assert_equal [@root.id, @child.id], body['ancestor_ids']
        assert_not body['truncated']

        tree = body['tree']
        assert_equal @root.identifier, tree['identifier']
        assert_equal 1, tree['sub_issue_count']
        assert_equal [@grandchild.id], tree['sub_issues'].first['sub_issues'].pluck('id')
        assert_equal [{ 'blocking_issue_id' => @child.id, 'blocked_issue_id' => @grandchild.id }], body['blocks']
      end

      test 'max_depth bounds the walk and reports truncation' do
        get api_v1_team_issue_hierarchy_path(@team, @root), params: { max_depth: 1 }, headers: @headers

        body = JSON.parse(response.body)
        assert body['truncated']
        assert_empty body['tree']['sub_issues'].first['sub_issues']
      end

      test 'returns not found for an issue on another team' do
        other_user = User.create!(name: 'Other', email: 'other_hierarchy@example.com', password: 'password')
        other_team = Workspace.create!(name: 'Other', owner: other_user).teams.create!(name: 'O', identifier: 'OHT')
        other_issue = other_team.issues.create!(title: 'X', lane: other_team.lanes.create!(name: 'B', position: 0),
                                                creator: other_user)

        get api_v1_team_issue_hierarchy_path(@team, other_issue), headers: @headers

        assert_response :not_found
      end

      private

      def create_issue(title, parent: nil)
        @team.issues.create!(title: title, lane: @backlog, creator: @user, parent_issue: parent)
      end
    end
  end
end
