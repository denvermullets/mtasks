require 'test_helper'

module Api
  module V1
    class TeamCommentsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'TC User', email: 'api_tc@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'ATC')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'Backlog', position: 0)
        @issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
        @project = @team.projects.create!(name: 'Proj')
        @headers = api_headers_for(@user)
      end

      test 'returns issue and project comments since the time, oldest first, with owners and parent_id' do
        t = Time.utc(2026, 1, 1, 12)
        old = @issue.comments.create!(user: @user, body: 'old')
        parent = @issue.comments.create!(user: @user, body: 'parent')
        reply = @issue.comments.create!(user: @user, body: 'reply', parent: parent)
        pc = @project.comments.create!(user: @user, body: 'proj')
        old.update_columns(updated_at: t - 1.second)
        pc.update_columns(updated_at: t)
        parent.update_columns(updated_at: t + 1.minute)
        reply.update_columns(updated_at: t + 2.minutes)

        get api_v1_team_comments_path(@team), params: { updated_since: t.iso8601 }, headers: @headers

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal [pc.id, parent.id, reply.id], body.pluck('id')
        assert_equal %w[Project Issue Issue], body.pluck('owner_type')
        assert_equal [@project.id, @issue.id, @issue.id], body.pluck('owner_id')
        assert_equal parent.id, body.last['parent_id']
        assert Time.iso8601(response.headers['X-Server-Time'])
      end

      test 'without updated_since returns all team comments' do
        @issue.comments.create!(user: @user, body: 'a')

        get api_v1_team_comments_path(@team), headers: @headers

        assert_response :success
        assert_equal 1, JSON.parse(response.body).size
      end

      test 'excludes other teams comments' do
        other = @workspace.teams.create!(name: 'O', identifier: 'OTC')
        other.team_memberships.create!(user: @user)
        other_lane = other.lanes.create!(name: 'B', position: 0)
        other.issues.create!(title: 'X', lane: other_lane, creator: @user).comments.create!(user: @user, body: 'secret')
        other.projects.create!(name: 'OP').comments.create!(user: @user, body: 'secret2')
        @issue.comments.create!(user: @user, body: 'mine')

        get api_v1_team_comments_path(@team), headers: @headers

        assert_equal ['mine'], JSON.parse(response.body).pluck('body')
      end

      test 'team outside the user returns 404' do
        stranger = User.create!(name: 'S', email: 'tc_s@example.com', password: 'password')

        get api_v1_team_comments_path(@team), headers: api_headers_for(stranger)

        assert_response :not_found
      end

      test 'invalid updated_since returns 422' do
        get api_v1_team_comments_path(@team), params: { updated_since: 'yesterday' }, headers: @headers

        assert_response :unprocessable_entity
        assert JSON.parse(response.body)['errors'].any?
      end
    end
  end
end
