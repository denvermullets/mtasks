require 'test_helper'

module HourglassLinks
  class DestroyServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @user = User.create!(name: 'DL', email: 'destroy_link@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @user)
      @team = @workspace.teams.create!(name: 'T', identifier: 'DLS')
      @team.team_memberships.create!(user: @user)
      @project = @team.projects.create!(name: 'Proj')
      @integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
        webhook_secret: 'wh', connected_by_user: @user
      )
      @link = HourglassLinks::CreateService.call(
        project: @project, channel_id: 'C42', channel_name: 'general',
        integration: @integration, current_user: @user
      ).link
    end

    test 'destroys the link and enqueues the destroyed-notify job' do
      assert_enqueued_with(job: HourglassNotifyLinkDestroyedJob) do
        assert_difference -> { HourglassLink.count }, -1 do
          result = HourglassLinks::DestroyService.call(link: @link)
          assert_nil result.error
        end
      end
    end
  end
end
