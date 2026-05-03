require 'test_helper'

module HourglassWebhookProcessor
  module Message
    class UnpinnedHandlerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @user = User.create!(name: 'UPH', email: "unpinned_handler_#{SecureRandom.hex(4)}@example.com",
                             password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'UPH')
        @team.team_memberships.create!(user: @user)
        @project = @team.projects.create!(name: 'Proj')
        @integration = create_integration
        @link = create_link
        @cache = create_pinned_cache
        @decision = create_decision
      end

      def create_integration
        @workspace.hourglass_integrations.create!(
          hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
          webhook_secret: 'wh', connected_by_user: @user
        )
      end

      def create_link
        @team.hourglass_links.create!(
          link_type: 'project_channel',
          mtasks_project: @project,
          hourglass_channel_id: 'C1',
          hourglass_channel_name: 'general',
          hourglass_integration: @integration,
          created_by_user: @user,
          status: 'active'
        )
      end

      def create_pinned_cache
        HourglassMessageCache.create!(
          hourglass_message_id: 'M1',
          hourglass_channel_id: 'C1',
          source: 'webhook',
          posted_at: 1.hour.ago,
          body: 'we will ship on Friday',
          pinned_at: 30.minutes.ago,
          pinned_by_email: @user.email
        )
      end

      def create_decision
        Decision.create!(
          team: @team,
          project: @project,
          hourglass_message_id: 'M1',
          pinned_at: @cache.pinned_at,
          body_snapshot: @cache.body
        )
      end

      def build_delivery(payload, event: 'message.unpinned')
        WebhookDelivery.create!(
          source: 'hourglass',
          delivery_id: SecureRandom.uuid,
          event_type: event,
          received_at: Time.current,
          payload: payload
        )
      end

      test 'unpin clears cache.pinned_at, sets Decision.unpinned_at, broadcasts replace' do
        delivery = build_delivery({ 'message_id' => 'M1', 'channel_id' => 'C1' })

        assert_enqueued_jobs 2, only: Turbo::Streams::ActionBroadcastJob do
          UnpinnedHandler.call(delivery, @integration)
        end

        @cache.reload
        assert_nil @cache.pinned_at
        assert_nil @cache.pinned_by_email

        assert_not_nil @decision.reload.unpinned_at
      end

      test 'unpin for unknown message_id is a logged no-op' do
        delivery = build_delivery({ 'message_id' => 'unknown' })

        assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
          assert_nothing_raised { UnpinnedHandler.call(delivery, @integration) }
        end
        assert_nil @decision.reload.unpinned_at
      end

      test 'unpin without an active decision leaves cache state but does not raise' do
        @decision.update!(unpinned_at: 1.minute.ago)
        delivery = build_delivery({ 'message_id' => 'M1' })

        assert_nothing_raised { UnpinnedHandler.call(delivery, @integration) }
        original_unpinned_at = @decision.unpinned_at
        assert_in_delta original_unpinned_at.to_i, @decision.reload.unpinned_at.to_i, 1
      end

      test 'missing message_id is logged and does not raise' do
        delivery = build_delivery({})

        assert_nothing_raised { UnpinnedHandler.call(delivery, @integration) }
      end
    end
  end
end
