require 'test_helper'

module HourglassWebhookProcessor
  module Link
    class CreatedHandlerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @user = User.create!(name: 'LCH', email: 'link_created@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'LCH')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'L', position: 0)
        @issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
        @integration = @workspace.hourglass_integrations.create!(
          hourglass_server_id: 'srv', hourglass_integration_id: 7,
          base_url: 'https://hg.test', api_token: 'tok', webhook_secret: 'wh',
          connected_by_user: @user
        )
      end

      def build_delivery(data, event: 'link.created')
        WebhookDelivery.create!(
          source: 'hourglass',
          delivery_id: SecureRandom.uuid,
          event_type: event,
          received_at: Time.current,
          payload: { 'event' => event, 'data' => data }
        )
      end

      test 'creates an issue_thread HourglassLink with notify_outbound suppressed' do
        assert_no_enqueued_jobs(only: HourglassNotifyThreadLinkCreatedJob) do
          assert_difference -> { HourglassLink.issue_thread.count }, 1 do
            CreatedHandler.call(
              build_delivery({
                               'link_type' => 'issue_thread',
                               'mtasks_issue_id' => @issue.id,
                               'hourglass_thread_id' => 'T_99',
                               'created_by_user_id' => @user.id
                             }),
              @integration
            )
          end
        end

        link = HourglassLink.for_issue(@issue).first
        assert_equal 'T_99', link.hourglass_thread_id
      end

      test 'idempotent when issue_thread link already exists' do
        @team.hourglass_links.create!(
          link_type: 'issue_thread', mtasks_issue: @issue,
          mtasks_issue_identifier: @issue.identifier, hourglass_thread_id: 'T_99',
          hourglass_integration: @integration, created_by_user: @user
        )

        assert_no_difference -> { HourglassLink.count } do
          CreatedHandler.call(
            build_delivery({
                             'link_type' => 'issue_thread',
                             'mtasks_issue_id' => @issue.id,
                             'hourglass_thread_id' => 'T_99'
                           }),
            @integration
          )
        end
      end

      test 'creates a project_channel HourglassLink with notify_outbound suppressed' do
        project = @team.projects.create!(name: 'P')

        assert_no_enqueued_jobs(only: HourglassNotifyLinkCreatedJob) do
          assert_difference -> { HourglassLink.project_channel.count }, 1 do
            CreatedHandler.call(
              build_delivery({
                               'link_type' => 'project_channel',
                               'mtasks_project_id' => project.id,
                               'hourglass_channel_id' => 'CCC',
                               'hourglass_channel_name' => 'general'
                             }),
              @integration
            )
          end
        end

        link = HourglassLink.for_project(project).first
        assert_equal 'CCC', link.hourglass_channel_id
      end

      test 'logs and skips on unknown link_type' do
        assert_no_difference -> { HourglassLink.count } do
          CreatedHandler.call(build_delivery({ 'link_type' => 'mystery' }), @integration)
        end
      end
    end
  end
end
