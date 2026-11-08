require 'test_helper'

class SubIssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Test User', email: 'sub_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'SUB')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)

    @parent = @team.issues.create!(title: 'Parent', lane: @lane, creator: @user)
    @child = @team.issues.create!(title: 'Child', lane: @lane, creator: @user, parent_issue: @parent)
    @loose = @team.issues.create!(title: 'Loose', lane: @lane, creator: @user)

    sign_in_as(@user)
  end

  test 'show renders the hierarchy section' do
    get team_issue_path(@team, @child)

    assert_response :success
    assert_select '#issue_hierarchy', text: /Sub-issue of/
  end

  test 'create attaches picked issues as sub-issues' do
    post team_issue_sub_issues_path(@team, @parent), params: { target_issue_ids: [@loose.id] }, as: :turbo_stream

    assert_response :success
    assert_equal @parent.id, @loose.reload.parent_issue_id
  end

  test 'create refuses to attach an ancestor and shows the error' do
    post team_issue_sub_issues_path(@team, @child), params: { target_issue_ids: [@parent.id] }, as: :turbo_stream

    assert_nil @parent.reload.parent_issue_id
    assert_includes response.body, 'circular'
  end

  test 'destroy detaches a sub-issue' do
    delete team_issue_sub_issue_path(@team, @parent, @child), as: :turbo_stream

    assert_nil @child.reload.parent_issue_id
  end

  test 'parent sets and clears the parent' do
    patch parent_team_issue_sub_issues_path(@team, @loose), params: { parent_issue_id: @child.id }, as: :turbo_stream
    assert_equal @child.id, @loose.reload.parent_issue_id

    patch parent_team_issue_sub_issues_path(@team, @loose), params: { parent_issue_id: '' }, as: :turbo_stream
    assert_nil @loose.reload.parent_issue_id
  end

  test 'parent search leaves out the issue and its descendants' do
    get search_team_issue_sub_issues_path(@team, @parent, mode: 'parent')

    assert_includes response.body, @loose.identifier
    assert_not_includes response.body, @child.identifier
  end

  test 'children search leaves out ancestors and existing sub-issues' do
    get search_team_issue_sub_issues_path(@team, @child)

    assert_includes response.body, @loose.identifier
    assert_not_includes response.body, @parent.identifier
  end

  test 'new prefills the parent and its project' do
    project = @team.projects.create!(name: 'Proj')
    @parent.update!(project: project)

    get new_team_issue_path(@team, parent_issue_id: @parent.id)

    assert_response :success
    assert_select "input[name='issue[parent_issue_id]'][value='#{@parent.id}']"
    assert_select "input[name='issue[project_id]'][value='#{project.id}']"
  end
end
