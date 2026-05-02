require 'test_helper'

module HourglassLinks
  class CreateServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @user = User.create!(name: 'CL', email: 'create_link@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @user)
      @team = @workspace.teams.create!(name: 'T', identifier: 'CLS')
      @team.team_memberships.create!(user: @user)
      @project = @team.projects.create!(name: 'Proj')
      @integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
        webhook_secret: 'wh', connected_by_user: @user
      )
    end

    test 'persists link and enqueues notify job' do
      assert_enqueued_with(job: HourglassNotifyLinkCreatedJob) do
        result = HourglassLinks::CreateService.call(
          project: @project,
          channel_id: 'C123',
          channel_name: 'general',
          integration: @integration,
          current_user: @user
        )

        assert_nil result.error
        assert_predicate result.link, :persisted?
        assert_equal 'general', result.link.hourglass_channel_name
        assert result.link.active?
      end
    end

    test 'returns error result when duplicate link for project' do
      HourglassLinks::CreateService.call(
        project: @project, channel_id: 'C1', channel_name: 'one',
        integration: @integration, current_user: @user
      )

      result = HourglassLinks::CreateService.call(
        project: @project, channel_id: 'C2', channel_name: 'two',
        integration: @integration, current_user: @user
      )

      assert_not_nil result.error
      assert_not result.link.persisted?
    end
  end
end
