require 'test_helper'

class ProjectDependencyMapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Project Map User', email: 'project_dependency_maps@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Project Map Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Project Map Team', identifier: 'PMP')
    @team.team_memberships.create!(user: @user)
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @project = @team.projects.create!(name: 'Launch')

    sign_in_as(@user)
  end

  test 'renders every linked issue with its edges and tags outside issues' do
    other = @team.projects.create!(name: 'Infra')
    a = create_issue('Alpha')
    b = create_issue('Bravo')
    outside = create_issue('Outside', project: other)
    IssueDependency.create!(blocking_issue: a, blocked_issue: b, kind: 'blocks')
    IssueDependency.create!(blocking_issue: outside, blocked_issue: a, kind: 'blocks')

    get team_project_dependency_map_path(@team, @project)

    assert_response :success
    assert_select "#dep_node_#{a.id}[href=?]", team_issue_dependency_map_path(@team, a)
    assert_select "#dep_node_#{b.id}"
    assert_select "#dep_node_#{outside.id}", text: /Infra/
    assert_select "#dep_node_#{a.id}", text: /Infra/, count: 0

    graph = css_select('[data-controller="dependency-map"]').first
    edges = JSON.parse(graph['data-dependency-map-edges-value'])
    assert_equal [[outside.id, a.id], [a.id, b.id]].sort, edges.map { |e| [e['from_id'], e['to_id']] }.sort
  end

  test 'shows the empty state when nothing is linked' do
    create_issue('Loner')

    get team_project_dependency_map_path(@team, @project)

    assert_response :success
    assert_match "No dependencies between this project's issues yet.", response.body
  end

  test "another team's project is not found" do
    other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'PMO')
    foreign = other_team.projects.create!(name: 'Foreign')

    get team_project_dependency_map_path(other_team, foreign)
    assert_response :not_found
  end

  private

  def create_issue(title, project: @project)
    @team.issues.create!(title: title, lane: @backlog, creator: @user, project: project)
  end
end
