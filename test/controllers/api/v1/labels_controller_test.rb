require 'test_helper'

module Api
  module V1
    class LabelsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_labels@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'ALB')
        @team.team_memberships.create!(user: @user)

        @label = @team.labels.create!(name: 'Bug', color: '#ef4444')
        @headers = api_headers_for(@user)
      end

      test 'lists labels' do
        get api_v1_team_labels_path(@team), headers: @headers

        assert_response :success
        labels = JSON.parse(response.body)
        assert_equal 1, labels.length
        assert_equal 'Bug', labels.first['name']
        assert_equal '#ef4444', labels.first['color']
      end

      test 'creates label' do
        assert_difference 'Label.count', 1 do
          post api_v1_team_labels_path(@team),
               params: { label: { name: 'Feature', color: '#3b82f6' } }.to_json,
               headers: @headers
        end

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'Feature', json['name']
        assert_equal '#3b82f6', json['color']
      end

      test 'returns validation errors for invalid label' do
        post api_v1_team_labels_path(@team),
             params: { label: { name: '', color: '' } }.to_json,
             headers: @headers

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert(json['errors'].any? { |e| e.include?('Name') })
      end

      test 'creates label with random color when none provided' do
        post api_v1_team_labels_path(@team),
             params: { label: { name: 'No Color' } }.to_json,
             headers: @headers

        assert_response :created
        json = JSON.parse(response.body)
        assert_equal 'No Color', json['name']
        assert_match(/\A#[0-9a-f]{6}\z/i, json['color'])
      end

      test 'returns error for duplicate label name' do
        post api_v1_team_labels_path(@team),
             params: { label: { name: 'Bug', color: '#000000' } }.to_json,
             headers: @headers

        assert_response :unprocessable_entity
      end

      test 'renames and recolors a label' do
        patch api_v1_team_label_path(@team, @label),
              params: { label: { name: 'Defect', color: '#000000' } }.to_json, headers: @headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 'Defect', json['name']
        assert_equal '#000000', json['color']
        assert_equal @label.reload.updated_at.iso8601(3), Time.zone.parse(json['updated_at']).iso8601(3)
        assert_equal 'Defect', @label.name
      end

      test 'list and create JSON include updated_at' do
        get api_v1_team_labels_path(@team), headers: @headers
        assert JSON.parse(response.body).first['updated_at'].present?
      end

      test 'update rejects blank name' do
        patch api_v1_team_label_path(@team, @label),
              params: { label: { name: '' } }.to_json, headers: @headers

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert_equal 'Unprocessable Entity', json['error']
        assert(json['errors'].any? { |e| e.include?('Name') })
      end

      test 'update rejects duplicate name' do
        @team.labels.create!(name: 'Other', color: '#111111')
        patch api_v1_team_label_path(@team, @label),
              params: { label: { name: 'other' } }.to_json, headers: @headers

        assert_response :unprocessable_entity
        assert_equal 'Bug', @label.reload.name
      end

      test 'update with a read-only token is forbidden' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])
        patch api_v1_team_label_path(@team, @label),
              params: { label: { name: 'X' } }.to_json,
              headers: { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        assert_response :forbidden
      end

      test 'update on a team outside the token is not found' do
        other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
        other_team.team_memberships.create!(user: @user)
        other_label = other_team.labels.create!(name: 'Elsewhere', color: '#222222')
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        patch api_v1_team_label_path(other_team, other_label),
              params: { label: { name: 'X' } }.to_json, headers: headers

        assert_response :not_found
        assert_equal 'Elsewhere', other_label.reload.name
      end

      test 'update on a label from another team is not found' do
        other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
        other_team.team_memberships.create!(user: @user)
        other_label = other_team.labels.create!(name: 'Elsewhere', color: '#222222')

        patch api_v1_team_label_path(@team, other_label),
              params: { label: { name: 'X' } }.to_json, headers: @headers

        assert_response :not_found
        assert_equal 'Elsewhere', other_label.reload.name
      end

      test 'deletes a label and removes it from the index' do
        delete api_v1_team_label_path(@team, @label), headers: @headers

        assert_response :no_content
        assert_not Label.exists?(@label.id)
        get api_v1_team_labels_path(@team), headers: @headers
        assert_empty JSON.parse(response.body)
      end

      test 'deleting a label touches carrying issues so they show up in updated_since without it' do
        lane = @team.lanes.create!(name: 'Backlog', position: 0)
        issue = @team.issues.create!(title: 'Carrier', lane: lane, creator: @user)
        issue.update!(label_ids: [@label.id])
        issue.update_columns(updated_at: 1.day.ago)
        since = 1.hour.ago.utc.iso8601(6)

        delete api_v1_team_label_path(@team, @label), headers: @headers

        get api_v1_team_issues_path(@team), params: { updated_since: since }, headers: @headers
        assert_response :success
        row = JSON.parse(response.body).find { |i| i['id'] == issue.id }
        assert row, 'carrying issue missing from updated_since pull'
        assert_empty Array(row['labels'])
      end

      test 'a deleted label appears in the team deleted feed' do
        label_id = @label.id
        delete api_v1_team_label_path(@team, @label), headers: @headers

        get api_v1_team_deleted_path(@team), headers: @headers
        body = JSON.parse(response.body)
        assert_includes body.map { |e| e.values_at('record_type', 'record_id') }, ['Label', label_id]
      end

      test 'delete with a read-only token is forbidden' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])
        delete api_v1_team_label_path(@team, @label),
               headers: { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        assert_response :forbidden
        assert Label.exists?(@label.id)
      end

      test 'delete on a team outside the token is not found' do
        other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
        other_team.team_memberships.create!(user: @user)
        other_label = other_team.labels.create!(name: 'Elsewhere', color: '#222222')
        token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        delete api_v1_team_label_path(other_team, other_label), headers: headers

        assert_response :not_found
        assert Label.exists?(other_label.id)
      end

      test 'delete on a label from another team is not found' do
        other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
        other_label = other_team.labels.create!(name: 'Elsewhere', color: '#222222')

        delete api_v1_team_label_path(@team, other_label), headers: @headers

        assert_response :not_found
        assert Label.exists?(other_label.id)
      end
    end
  end
end
