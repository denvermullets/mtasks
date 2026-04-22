require 'test_helper'

class RoadmapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Roadmap User', email: 'roadmap@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Roadmap Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Roadmap Team', identifier: 'RDM')
    @team.team_memberships.create!(user: @user)

    @now_project = @team.projects.create!(name: 'Now project', roadmap_commitment: 'now')
    @next_project = @team.projects.create!(name: 'Next project', roadmap_commitment: 'next')
    @later_project = @team.projects.create!(name: 'Later project', roadmap_commitment: 'later')
    @off_project = @team.projects.create!(name: 'Off roadmap', roadmap_commitment: nil)

    sign_in_as(@user)
  end

  test 'show renders all three lanes with their projects' do
    get team_roadmap_path(@team)

    assert_response :success
    assert_includes response.body, 'Now project'
    assert_includes response.body, 'Next project'
    assert_includes response.body, 'Later project'
    assert_includes response.body, 'Now / next / later'
  end

  test 'projects without a commitment do not appear in any lane grid' do
    get team_roadmap_path(@team)

    assert_response :success
    # Off-roadmap project only appears in the "Add project" picker, not the lane grid
    # We just ensure it's not rendered inside a roadmap card
    assert_no_match(/id="roadmap_card_project_#{@off_project.id}"/, response.body)
    assert_match(/id="roadmap_card_project_#{@now_project.id}"/, response.body)
  end

  test 'requires team membership' do
    delete session_path # sign out
    other_user = User.create!(name: 'Other', email: 'other@example.com', password: 'password')
    sign_in_as(other_user)

    get team_roadmap_path(@team)
    # Redirected because user is not a team member
    assert_response :redirect
  end
end
