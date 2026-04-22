require 'test_helper'

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Test User', email: 'proj_ctrl@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'PCT')
    @team.team_memberships.create!(user: @user)

    @project = @team.projects.create!(name: 'Test Project', description: 'A project', status: 'backlog')

    sign_in_as(@user)
  end

  test 'index lists projects' do
    get team_projects_path(@team)
    assert_response :success
    assert_includes response.body, 'Test Project'
  end

  test 'show displays project' do
    get team_project_path(@team, @project)
    assert_response :success
    assert_includes response.body, 'Test Project'
  end

  test 'new renders form' do
    get new_team_project_path(@team)
    assert_response :success
  end

  test 'creates project' do
    assert_difference 'Project.count', 1 do
      post team_projects_path(@team),
           params: { project: { name: 'New Project', status: 'backlog', priority: 'medium' } }
    end

    assert_redirected_to team_project_path(@team, Project.last)
  end

  test 'create with invalid params renders errors' do
    assert_no_difference 'Project.count' do
      post team_projects_path(@team), params: { project: { name: '' } }
    end

    assert_response :unprocessable_entity
  end

  test 'edit renders form' do
    get edit_team_project_path(@team, @project)
    assert_response :success
  end

  test 'updates project' do
    patch team_project_path(@team, @project),
          params: { project: { name: 'Updated', status: 'started' } }

    assert_redirected_to team_project_path(@team, @project)
    @project.reload
    assert_equal 'Updated', @project.name
    assert_equal 'started', @project.status
  end

  test 'destroys project' do
    assert_difference 'Project.count', -1 do
      delete team_project_path(@team, @project)
    end

    assert_redirected_to team_projects_path(@team)
  end

  test 'show displays project issues' do
    lane = @team.lanes.create!(name: 'Backlog', position: 0)
    @team.issues.create!(title: 'Project Issue', lane: lane, creator: @user, project: @project)

    get team_project_path(@team, @project)
    assert_response :success
    assert_includes response.body, 'Project Issue'
  end

  test 'update sets roadmap_commitment and responds with turbo_stream' do
    patch team_project_path(@team, @project),
          params: { project: { roadmap_commitment: 'now' } },
          as: :turbo_stream

    assert_response :success
    assert_equal 'now', @project.reload.roadmap_commitment
    assert_match(/turbo-stream/, @response.content_type)
  end

  test 'update clears roadmap_commitment when blank' do
    @project.update!(roadmap_commitment: 'next')

    patch team_project_path(@team, @project),
          params: { project: { roadmap_commitment: '' } },
          as: :turbo_stream

    assert_response :success
    assert_nil @project.reload.roadmap_commitment
  end
end
