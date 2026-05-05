require 'test_helper'

module HourglassWebhookProcessor
  module Link
    class RemovedHandlerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @user = User.create!(name: 'LRH', email: 'link_removed@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'LRH')
        @team.team_memberships.create!(user: @user)
        @lane = @team.lanes.create!(name: 'L', position: 0)
        @issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
        @integration = @workspace.hourglass_integrations.create!(
          hourglass_server_id: 'srv', hourglass_integration_id: 7,
          base_url: 'https://hg.test', api_token: 'tok', webhook_secret: 'wh',
          connected_by_user: @user
        )
      end

      def build_delivery(data)
        WebhookDelivery.create!(
          source: 'hourglass',
          delivery_id: SecureRandom.uuid,
          event_type: 'link.removed',
          received_at: Time.current,
          payload: { 'event' => 'link.removed', 'data' => data }
        )
      end

      test 'destroys matching issue_thread link with notify suppressed' do
        link = @team.hourglass_links.create!(
          link_type: 'issue_thread', mtasks_issue: @issue,
          mtasks_issue_identifier: @issue.identifier, hourglass_thread_id: 'T_X',
          hourglass_integration: @integration, created_by_user: @user
        )

        assert_no_enqueued_jobs(only: HourglassNotifyThreadLinkDestroyedJob) do
          assert_difference -> { HourglassLink.count }, -1 do
            RemovedHandler.call(
              build_delivery({
                               'link_type' => 'issue_thread',
                               'mtasks_issue_id' => @issue.id,
                               'hourglass_thread_id' => 'T_X'
                             }),
              @integration
            )
          end
        end

        assert_nil HourglassLink.find_by(id: link.id)
      end

      test 'idempotent when no matching link exists' do
        assert_no_difference -> { HourglassLink.count } do
          RemovedHandler.call(
            build_delivery({ 'link_type' => 'issue_thread', 'hourglass_thread_id' => 'T_NONE' }),
            @integration
          )
        end
      end

      test 'destroys matching project_channel link with notify suppressed' do
        project = @team.projects.create!(name: 'P')
        link = @team.hourglass_links.create!(
          link_type: 'project_channel', mtasks_project: project,
          hourglass_channel_id: 'CCC', hourglass_integration: @integration, created_by_user: @user
        )

        assert_no_enqueued_jobs(only: HourglassNotifyLinkDestroyedJob) do
          assert_difference -> { HourglassLink.count }, -1 do
            RemovedHandler.call(
              build_delivery({
                               'link_type' => 'project_channel',
                               'mtasks_project_id' => project.id,
                               'hourglass_channel_id' => 'CCC'
                             }),
              @integration
            )
          end
        end

        assert_nil HourglassLink.find_by(id: link.id)
      end
    end
  end
end
