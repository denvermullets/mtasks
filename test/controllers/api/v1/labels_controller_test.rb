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
    end
  end
end
