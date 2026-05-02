require 'test_helper'

module Api
  module V1
    class IssuesByIdentifierTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'BI User', email: "bi_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @workspace = Workspace.create!(name: 'BI WS', owner: @user)
        @team = @workspace.teams.create!(name: 'BI Team', identifier: 'BIT')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'Backlog', position: 0)
        @issue = @team.issues.create!(title: 'Findable', lane: @lane, creator: @user)
        @headers = api_headers_for(@user)
      end

      test 'returns the matching issue' do
        get "/api/v1/issues/by_identifier/#{@issue.identifier}", headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal @issue.id, json['id']
        assert_equal @issue.identifier, json['identifier']
      end

      test 'requires a token' do
        get "/api/v1/issues/by_identifier/#{@issue.identifier}",
            headers: { 'Content-Type' => 'application/json' }
        assert_response :unauthorized
      end

      test 'returns 404 when team identifier is not in current_user teams' do
        outsider = User.create!(name: 'Outsider', email: "out_bi_#{SecureRandom.hex(4)}@example.com",
                                password: 'password')
        out_headers = api_headers_for(outsider)

        get "/api/v1/issues/by_identifier/#{@issue.identifier}", headers: out_headers
        assert_response :not_found
      end

      test 'returns 404 for unknown number in known team' do
        get "/api/v1/issues/by_identifier/#{@team.identifier}-9999", headers: @headers
        assert_response :not_found
      end

      test 'returns 404 for malformed identifier' do
        # Route constraint blocks lower-case or missing dash; falls through to 404.
        get '/api/v1/issues/by_identifier/notvalid', headers: @headers
        assert_response :not_found
      end

      test 'team-scoped token only resolves issues from that team' do
        other_team = @workspace.teams.create!(name: 'Other', identifier: 'OTH')
        other_team.team_memberships.create!(user: @user)
        other_lane = other_team.lanes.create!(name: 'Backlog', position: 0)
        other_issue = other_team.issues.create!(title: 'Other', lane: other_lane, creator: @user)

        scoped = ApiToken.generate_for(@user, name: 'scoped', team: @team)
        scoped_headers = { 'Authorization' => "Bearer #{scoped.raw_token}", 'Content-Type' => 'application/json' }

        get "/api/v1/issues/by_identifier/#{other_issue.identifier}", headers: scoped_headers
        assert_response :not_found

        get "/api/v1/issues/by_identifier/#{@issue.identifier}", headers: scoped_headers
        assert_response :success
      end
    end
  end
end
