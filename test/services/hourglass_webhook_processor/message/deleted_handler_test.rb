require 'test_helper'

module HourglassWebhookProcessor
  module Message
    class DeletedHandlerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @user = User.create!(name: 'DH', email: 'deleted_handler@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'DLH')
        @team.team_memberships.create!(user: @user)
        @project = @team.projects.create!(name: 'Proj')
        @integration = @workspace.hourglass_integrations.create!(
          hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
          webhook_secret: 'wh', connected_by_user: @user
        )
        @link = @team.hourglass_links.create!(
          link_type: 'project_channel',
          mtasks_project: @project,
          hourglass_channel_id: 'C1',
          hourglass_integration: @integration,
          created_by_user: @user
        )
        @cache = HourglassMessageCache.create!(
          hourglass_message_id: 'M1',
          hourglass_channel_id: 'C1',
          body: 'goodbye',
          posted_at: 1.minute.ago,
          source: 'webhook'
        )
      end

      def build_delivery(payload, event: 'message.deleted')
        WebhookDelivery.create!(
          source: 'hourglass', delivery_id: SecureRandom.uuid,
          event_type: event, received_at: Time.current, payload: payload
        )
      end

      test 'sets deleted_at and broadcasts replace (not remove)' do
        delivery = build_delivery({ 'message_id' => 'M1' })

        assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
          DeletedHandler.call(delivery, @integration)
        end

        assert_not_nil @cache.reload.deleted_at
      end

      test 'no-op for unknown message' do
        delivery = build_delivery({ 'message_id' => 'M_missing' })

        assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
          DeletedHandler.call(delivery, @integration)
        end
      end

      test 'loop guard skips when comment owns message_id' do
        @project.comments.create!(
          user: @user, body: 'pushed', pushed_to_hourglass_message_id: 'M1'
        )
        delivery = build_delivery({ 'message_id' => 'M1' })

        assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
          DeletedHandler.call(delivery, @integration)
        end
        assert_nil @cache.reload.deleted_at
      end
    end
  end
end
