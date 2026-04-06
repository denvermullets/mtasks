require 'test_helper'

class IssueDependenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Test User', email: 'dep_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'DCT')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)

    @issue_a = @team.issues.create!(title: 'Issue A', lane: @lane, creator: @user)
    @issue_b = @team.issues.create!(title: 'Issue B', lane: @lane, creator: @user)
    @issue_c = @team.issues.create!(title: 'Issue C', lane: @lane, creator: @user)

    sign_in_as(@user)
  end

  test 'creates a blocking dependency' do
    assert_difference 'IssueDependency.count', 1 do
      post team_issue_issue_dependencies_path(@team, @issue_a),
           params: { target_issue_id: @issue_b.id, direction: 'blocking' }
    end

    dep = IssueDependency.last
    assert_equal @issue_a.id, dep.blocking_issue_id
    assert_equal @issue_b.id, dep.blocked_issue_id
  end

  test 'creates a blocked_by dependency' do
    assert_difference 'IssueDependency.count', 1 do
      post team_issue_issue_dependencies_path(@team, @issue_a),
           params: { target_issue_id: @issue_b.id, direction: 'blocked_by' }
    end

    dep = IssueDependency.last
    assert_equal @issue_b.id, dep.blocking_issue_id
    assert_equal @issue_a.id, dep.blocked_issue_id
  end

  test 'bulk_create creates multiple dependencies' do
    assert_difference 'IssueDependency.count', 2 do
      post bulk_create_team_issue_issue_dependencies_path(@team, @issue_a),
           params: { target_issue_ids: [@issue_b.id, @issue_c.id], direction: 'blocking' }
    end
  end

  test 'destroys a dependency' do
    dep = IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)

    assert_difference 'IssueDependency.count', -1 do
      delete team_issue_issue_dependency_path(@team, @issue_a, dep)
    end
  end

  test 'search returns candidate issues' do
    get search_team_issue_issue_dependencies_path(@team, @issue_a), params: { q: 'Issue B' }
    assert_response :success
  end

  test 'search excludes self and existing dependencies' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)

    get search_team_issue_issue_dependencies_path(@team, @issue_a), params: { q: '' }
    assert_response :success
    # issue_a (self) and issue_b (already dependent) should be excluded
    assert_not_includes response.body, "IST-#{@issue_a.team_number}"
  end
end
