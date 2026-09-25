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

  test 'creates a relates dependency' do
    post team_issue_issue_dependencies_path(@team, @issue_a),
         params: { target_issue_id: @issue_b.id, direction: 'relates' }

    dep = IssueDependency.last
    assert dep.relates?
    assert_equal @issue_a.id, dep.blocking_issue_id
    assert_equal @issue_b.id, dep.blocked_issue_id
  end

  test 'creates a duplicated_by dependency' do
    post team_issue_issue_dependencies_path(@team, @issue_a),
         params: { target_issue_id: @issue_b.id, direction: 'duplicated_by' }

    dep = IssueDependency.last
    assert dep.duplicates?
    assert_equal @issue_b.id, dep.blocking_issue_id
    assert_equal @issue_a.id, dep.blocked_issue_id
  end

  test 'bulk_create links related issues' do
    assert_difference -> { IssueDependency.relates.count }, 2 do
      post bulk_create_team_issue_issue_dependencies_path(@team, @issue_a),
           params: { target_issue_ids: [@issue_b.id, @issue_c.id], direction: 'relates' },
           as: :turbo_stream
    end
    assert_response :success
    assert_includes response.body, 'Related'
  end

  test 'destroys a relates dependency by record id from either side' do
    dep = IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b, kind: :relates)

    assert_difference 'IssueDependency.count', -1 do
      delete team_issue_issue_dependency_path(@team, @issue_b, dep), as: :turbo_stream
    end
  end

  test 'destroys a relates dependency by the other issue id' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b, kind: :relates)

    assert_difference 'IssueDependency.count', -1 do
      delete team_issue_issue_dependency_path(@team, @issue_a, @issue_b.id), as: :turbo_stream
    end
  end

  test 'search excludes issues linked by any kind' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b, kind: :relates)
    IssueDependency.create!(blocking_issue: @issue_c, blocked_issue: @issue_a, kind: :duplicates)

    get search_team_issue_issue_dependencies_path(@team, @issue_a), params: { q: '' }
    assert_response :success
    assert_not_includes response.body, @issue_b.identifier
    assert_not_includes response.body, @issue_c.identifier
  end

  test 'a cycle re-renders the relations with an error instead of failing' do
    IssueDependency.create!(blocking_issue: @issue_a, blocked_issue: @issue_b)
    IssueDependency.create!(blocking_issue: @issue_b, blocked_issue: @issue_c)

    assert_no_difference 'IssueDependency.count' do
      post team_issue_issue_dependencies_path(@team, @issue_c),
           params: { target_issue_id: @issue_a.id, direction: 'blocking' }, as: :turbo_stream
    end
    assert_response :success
    assert_includes response.body, 'Would create a circular dependency'
  end
end
