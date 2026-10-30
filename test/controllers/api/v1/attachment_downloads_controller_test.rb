require 'test_helper'

module Api
  module V1
    class AttachmentDownloadsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Dl User', email: "dl_#{SecureRandom.hex(4)}@example.com", password: 'password')
        @workspace = Workspace.create!(name: 'Dl WS', owner: @user)
        @team = @workspace.teams.create!(name: 'Dl Team', identifier: 'DLT')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'Backlog', position: 0)
        @issue = @team.issues.create!(title: 'Has files', lane: @lane, creator: @user)
        @token = ApiToken.generate_for(@user)
        @headers = { 'Authorization' => "Bearer #{@token.raw_token}", 'Content-Type' => 'application/json' }
      end

      def attach_to(record, name = 'a.txt')
        record.files.attach(io: StringIO.new('hello'), filename: name, content_type: 'text/plain')
        record.files_attachments.order(:id).last
      end

      def download(attachment, headers: @headers)
        get "/api/v1/attachments/#{attachment.id}/download", headers: headers
      end

      def other_team
        owner = User.create!(name: 'Other', email: "o_#{SecureRandom.hex(4)}@example.com", password: 'password')
        Workspace.create!(name: 'Other WS', owner: owner).teams.create!(name: 'Other', identifier: 'OTH').tap do |team|
          team.lanes.create!(name: 'Backlog', position: 0)
        end
      end

      test 'issue attachment redirects to a storage url that expires in five minutes' do
        download(attach_to(@issue))

        assert_response :redirect
        key = response.location[%r{/disk/([^/]+)/}, 1]
        data = ActiveStorage.verifier.verified(key, purpose: :blob_key)
        assert data

        travel 4.minutes do
          assert ActiveStorage.verifier.verified(key, purpose: :blob_key)
        end
        travel 6.minutes do
          assert_nil ActiveStorage.verifier.verified(key, purpose: :blob_key)
        end
      end

      test 'project, issue comment and project comment attachments are served' do
        project = @team.projects.create!(name: 'P', lead: @user)
        issue_comment = @issue.comments.create!(user: @user, body: 'hi')
        project_comment = project.comments.create!(user: @user, body: 'hi')

        [project, issue_comment, project_comment].each do |record|
          download(attach_to(record))
          assert_response :redirect
        end
      end

      test 'attachments on another team issue, project and comment are 404' do
        team = other_team
        owner = team.workspace.owner
        issue = team.issues.create!(title: 'Theirs', lane: team.lanes.first, creator: owner)
        project = team.projects.create!(name: 'P', lead: owner)

        [issue, project, issue.comments.create!(user: owner, body: 'x'),
         project.comments.create!(user: owner, body: 'x')].each do |record|
          download(attach_to(record))
          assert_response :not_found
        end
      end

      test 'unknown attachment is 404' do
        get '/api/v1/attachments/999999/download', headers: @headers

        assert_response :not_found
      end

      test 'missing token is 401' do
        get "/api/v1/attachments/#{attach_to(@issue).id}/download"

        assert_response :unauthorized
      end

      test 'revoked token is 401' do
        attachment = attach_to(@issue)
        @token.revoke!

        download(attachment)

        assert_response :unauthorized
      end

      test 'token scoped away from the owning team is 404' do
        attachment = attach_to(@issue)
        second = @workspace.teams.create!(name: 'Second', identifier: 'SEC')
        second.team_memberships.create!(user: @user)
        @token.scope_to_teams!(Team.where(id: second.id))

        download(attachment)

        assert_response :not_found
      end
    end
  end
end
