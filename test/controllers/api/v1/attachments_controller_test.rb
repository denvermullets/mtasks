require 'test_helper'

module Api
  module V1
    class AttachmentsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Att User', email: "att_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @workspace = Workspace.create!(name: 'Att WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Att Team', identifier: 'ATT')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'Backlog', position: 0)
        @issue = @team.issues.create!(title: 'Has files', lane: @lane, creator: @user)
        @headers = api_headers_for(@user)
      end

      def signed_id(name = 'a.txt')
        ActiveStorage::Blob.create_and_upload!(io: StringIO.new('hello'), filename: name, content_type: 'text/plain')
                           .signed_id
      end

      def attach(ids, headers: @headers, issue: @issue, team: @team)
        post api_v1_team_issue_attachments_path(team, issue), params: { signed_ids: ids }.to_json, headers: headers
      end

      test 'attaching signed ids lists files on issue show and detail index' do
        attach([signed_id('a.txt'), signed_id('b.txt')])

        assert_response :created
        assert_equal %w[a.txt b.txt], response.parsed_body.pluck('filename')
        assert response.parsed_body.first['download_url'].present?

        get api_v1_team_issue_path(@team, @issue), headers: @headers
        assert_equal %w[a.txt b.txt], response.parsed_body['files'].pluck('filename')

        get api_v1_team_issues_path(@team), params: { include: 'detail' }, headers: @headers
        assert_equal %w[a.txt b.txt], response.parsed_body.first['files'].pluck('filename')
      end

      test 'issue with no files has an empty files list' do
        get api_v1_team_issue_path(@team, @issue), headers: @headers

        assert_equal [], response.parsed_body['files']
      end

      test 'deleting an attachment returns 204 and removes it from files' do
        attach([signed_id])
        id = response.parsed_body.first['id']

        delete api_v1_team_issue_attachment_path(@team, @issue, id), headers: @headers
        assert_response :no_content

        get api_v1_team_issue_path(@team, @issue), headers: @headers
        assert_equal [], response.parsed_body['files']
      end

      test 'deleting an unknown attachment returns 404' do
        delete api_v1_team_issue_attachment_path(@team, @issue, 999_999), headers: @headers

        assert_response :not_found
      end

      test 'attach and detach make the issue appear in the next updated_since pull' do
        @issue.update_columns(updated_at: 1.day.ago)
        since = 1.hour.ago.iso8601
        attach([signed_id])
        get api_v1_team_issues_path(@team), params: { updated_since: since }, headers: @headers
        assert_equal [@issue.id], response.parsed_body.pluck('id')

        @issue.update_columns(updated_at: 1.day.ago)
        delete api_v1_team_issue_attachment_path(@team, @issue, @issue.files_attachments.first.id), headers: @headers
        get api_v1_team_issues_path(@team), params: { updated_since: since }, headers: @headers
        assert_equal [@issue.id], response.parsed_body.pluck('id')
      end

      test 'invalid or missing signed ids return 422 and attach nothing' do
        [['garbage'], [signed_id, 'garbage'], []].each do |ids|
          attach(ids)

          assert_response :unprocessable_entity
        end
        assert_equal 0, @issue.reload.files.count
      end

      test 'no token returns 401' do
        attach([signed_id], headers: { 'Content-Type' => 'application/json' })

        assert_response :unauthorized
      end

      test 'read-only token returns 403 on attach and detach' do
        ro = ApiToken.generate_for(@user, name: 'ro', scopes: %w[read])
        headers = { 'Authorization' => "Bearer #{ro.raw_token}", 'Content-Type' => 'application/json' }

        attach([signed_id], headers: headers)
        assert_response :forbidden

        delete api_v1_team_issue_attachment_path(@team, @issue, 1), headers: headers
        assert_response :forbidden
      end

      test 'team outside the token returns 404' do
        outsider = User.create!(name: 'Out', email: "out_#{SecureRandom.hex(4)}@example.com", password: 'password')
        out_team = Workspace.create!(name: 'Out WS', owner: outsider).teams.create!(name: 'Out', identifier: 'OUT')
        out_issue = out_team.issues.create!(title: 't', lane: out_team.lanes.create!(name: 'B', position: 0),
                                            creator: outsider)

        attach([signed_id], issue: out_issue, team: out_team)

        assert_response :not_found
      end

      test 'issue from another team under a valid team returns 404' do
        other = @workspace.teams.create!(name: 'Other', identifier: 'OTH')
        other.team_memberships.create!(user: @user)
        foreign = other.issues.create!(title: 'x', lane: other.lanes.create!(name: 'B', position: 0), creator: @user)

        attach([signed_id], issue: foreign)

        assert_response :not_found
      end
    end
  end
end
