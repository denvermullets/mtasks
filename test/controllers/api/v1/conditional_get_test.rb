require 'test_helper'

module Api
  module V1
    class ConditionalGetTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'Etag User', email: 'api_etag@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'Etag Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'Etag Team', identifier: 'ETG')
        @team.team_memberships.create!(user: @user)
        @other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
        @other_team.team_memberships.create!(user: @user)
        @team.labels.create!(name: 'Bug', color: '#ef4444')
        @headers = api_headers_for(@user)
      end

      {
        lanes: ->(t) { api_v1_team_lanes_path(t) },
        labels: ->(t) { api_v1_team_labels_path(t) },
        members: ->(t) { api_v1_team_members_path(t) }
      }.each do |name, path|
        test "#{name} returns an etag and 304s when unchanged" do
          get instance_exec(@team, &path), headers: @headers
          assert_response :success
          etag = response.headers['ETag']
          assert etag.present?

          get instance_exec(@team, &path), headers: @headers.merge('If-None-Match' => etag)
          assert_response :not_modified
          assert response.body.blank?
        end

        test "#{name} etag differs between teams" do
          get instance_exec(@team, &path), headers: @headers
          etag = response.headers['ETag']
          get instance_exec(@other_team, &path), headers: @headers
          assert_response :success
          assert_not_equal etag, response.headers['ETag'] if name == :labels
        end
      end

      test 'lanes change yields 200 with a new etag' do
        get api_v1_team_lanes_path(@team), headers: @headers
        etag = response.headers['ETag']
        @team.lanes.order(:position).first.update!(name: 'Renamed lane')

        get api_v1_team_lanes_path(@team), headers: @headers.merge('If-None-Match' => etag)
        assert_response :success
        assert_not_equal etag, response.headers['ETag']
      end

      test 'labels change yields 200 with a new etag' do
        get api_v1_team_labels_path(@team), headers: @headers
        etag = response.headers['ETag']
        @team.labels.create!(name: 'Feature', color: '#22c55e')

        get api_v1_team_labels_path(@team), headers: @headers.merge('If-None-Match' => etag)
        assert_response :success
        assert_not_equal etag, response.headers['ETag']
      end

      test 'members change yields 200 with a new etag' do
        get api_v1_team_members_path(@team), headers: @headers
        etag = response.headers['ETag']
        newcomer = User.create!(name: 'New Member', email: 'etag_new@example.com', password: 'password')
        @team.team_memberships.create!(user: newcomer)

        get api_v1_team_members_path(@team), headers: @headers.merge('If-None-Match' => etag)
        assert_response :success
        assert_not_equal etag, response.headers['ETag']
      end
    end
  end
end
