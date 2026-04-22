require 'test_helper'

module Api
  module V1
    class ProjectsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_projects@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'APJ')
        @team.team_memberships.create!(user: @user)

        @project = @team.projects.create!(name: 'Test Project', description: 'A test project')
        @headers = api_headers_for(@user)
      end

      # Index
      test 'lists projects' do
        get api_v1_team_projects_path(@team), headers: @headers

        assert_response :success
        projects = JSON.parse(response.body)
        assert_equal 1, projects.length
        assert_equal 'Test Project', projects.first['name']
      end

      # Show
      test 'shows project with details' do
        get api_v1_team_project_path(@team, @project), headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal @project.id, json['id']
        assert_equal 'Test Project', json['name']
        assert json.key?('labels')
        assert json.key?('issues_count')
      end

      test 'returns not found for non-existent project' do
        get api_v1_team_project_path(@team, 999_999), headers: @headers
        assert_response :not_found
      end

      # Create
      test 'creates project' do
        assert_difference 'Project.count', 1 do
          post api_v1_team_projects_path(@team),
               params: { project: { name: 'New Project', status: 'backlog', priority: 'medium' } }.to_json,
               headers: @headers
        end

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'New Project', json['name']
        assert_equal 'backlog', json['status']
      end

      test 'returns validation errors for invalid project' do
        post api_v1_team_projects_path(@team),
             params: { project: { name: '' } }.to_json,
             headers: @headers

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert(json['errors'].any? { |e| e.include?('Name') })
      end

      # Update
      test 'updates project' do
        patch api_v1_team_project_path(@team, @project),
              params: { project: { name: 'Updated Name', status: 'started' } }.to_json,
              headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 'Updated Name', json['name']
        assert_equal 'started', json['status']
      end

      test 'updates roadmap_commitment' do
        patch api_v1_team_project_path(@team, @project),
              params: { project: { roadmap_commitment: 'now' } }.to_json,
              headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 'now', json['roadmap_commitment']
        assert_equal 'now', @project.reload.roadmap_commitment
      end

      test 'show exposes roadmap_commitment' do
        @project.update!(roadmap_commitment: 'later')

        get api_v1_team_project_path(@team, @project), headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 'later', json['roadmap_commitment']
      end

      # Destroy
      test 'destroys project' do
        assert_difference 'Project.count', -1 do
          delete api_v1_team_project_path(@team, @project), headers: @headers
        end

        assert_response :no_content
      end
    end
  end
end
