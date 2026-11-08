require 'test_helper'

class IssueHierarchyQueryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Tree User', email: 'hierarchy_query@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Tree Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Tree Team', identifier: 'TRE')
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)

    @root = create_issue('Root')
    @child = create_issue('Child', parent: @root)
    @grandchild = create_issue('Grandchild', parent: @child)
    @sibling = create_issue('Sibling', parent: @root)
  end

  test 'walks up to the root and down through every level' do
    result = IssueHierarchyQuery.call(issue: @grandchild)

    assert_equal @root, result.root
    assert_equal [@root, @child], result.ancestors
    assert_equal [@child, @sibling], result.children_of(@root)
    assert_equal [@grandchild], result.children_of(@child)
    assert_empty result.children_of(@grandchild)
    assert_not result.truncated?
  end

  test 'a standalone issue is a single-node tree' do
    result = IssueHierarchyQuery.call(issue: create_issue('Alone'))

    assert result.single_issue?
    assert_empty result.ancestors
  end

  test 'archived sub-issues are left out and an archived parent is not the root' do
    @sibling.archive!
    @root.archive!
    result = IssueHierarchyQuery.call(issue: @grandchild)

    assert_equal @child, result.root
    assert_not_includes result.issues_by_id.keys, @sibling.id
  end

  test 'caps the downward walk and reports truncation' do
    result = IssueHierarchyQuery.call(issue: @root, max_depth: 1)

    assert_equal [@child, @sibling], result.children_of(@root)
    assert_empty result.children_of(@child)
    assert result.truncated?
  end

  test 'includes blocks edges between issues in the tree' do
    IssueDependency.create!(blocking_issue: @sibling, blocked_issue: @grandchild)

    result = IssueHierarchyQuery.call(issue: @root)

    assert_equal [{ from_id: @sibling.id, to_id: @grandchild.id, kind: 'blocks' }], result.edges
  end

  test 'terminates on a legacy parent cycle' do
    @root.update_column(:parent_issue_id, @grandchild.id)

    result = IssueHierarchyQuery.call(issue: @child)

    assert_includes result.issues_by_id.keys, @grandchild.id
  end

  private

  def create_issue(title, parent: nil)
    @team.issues.create!(title: title, lane: @lane, creator: @user, parent_issue: parent)
  end
end
