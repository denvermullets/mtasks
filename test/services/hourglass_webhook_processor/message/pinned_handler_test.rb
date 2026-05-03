require 'test_helper'

module HourglassWebhookProcessor
  module Message
    class PinnedHandlerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @user = User.create!(name: 'PH', email: "pinned_handler_#{SecureRandom.hex(4)}@example.com",
                             password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'PIN')
        @team.team_memberships.create!(user: @user)
        @project = @team.projects.create!(name: 'Proj')
        @integration = create_integration
        @link = create_link
        @cache = create_cache
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

      def create_cache
        HourglassMessageCache.create!(
          hourglass_message_id: 'M1',
          hourglass_channel_id: 'C1',
          source: 'webhook',
          posted_at: 1.hour.ago,
          body: 'we will ship on Friday'
        )
      end

      def build_delivery(payload, event: 'message.pinned')
        WebhookDelivery.create!(
          source: 'hourglass',
          delivery_id: SecureRandom.uuid,
          event_type: event,
          received_at: Time.current,
          payload: payload
        )
      end

      def basic_payload(overrides = {})
        {
          'message_id' => 'M1',
          'channel_id' => 'C1',
          'pinned_at' => '2026-05-02T10:00:00Z',
          'pinned_by' => { 'email' => @user.email }
        }.merge(overrides)
      end

      test 'pin creates Decision row, sets cache.pinned_at, broadcasts replace + append' do
        delivery = build_delivery(basic_payload)

        assert_difference -> { Decision.count }, 1 do
          assert_enqueued_jobs 2, only: Turbo::Streams::ActionBroadcastJob do
            PinnedHandler.call(delivery, @integration)
          end
        end

        @cache.reload
        assert_not_nil @cache.pinned_at
        assert_equal @user.email, @cache.pinned_by_email

        decision = Decision.find_by(hourglass_message_id: 'M1')
        assert_equal @project.id, decision.project_id
        assert_equal @team.id, decision.team_id
        assert_equal 'we will ship on Friday', decision.body_snapshot
        assert_nil decision.unpinned_at
      end

      test 'replay does not duplicate the Decision row' do
        PinnedHandler.call(build_delivery(basic_payload), @integration)

        assert_no_difference -> { Decision.count } do
          PinnedHandler.call(build_delivery(basic_payload), @integration)
        end
      end

      test 'body_snapshot is frozen at pin time and survives later message edits' do
        PinnedHandler.call(build_delivery(basic_payload), @integration)
        decision = Decision.find_by!(hourglass_message_id: 'M1')
        original_snapshot = decision.body_snapshot

        update_delivery = WebhookDelivery.create!(
          source: 'hourglass',
          delivery_id: SecureRandom.uuid,
          event_type: 'message.updated',
          received_at: Time.current,
          payload: { 'message_id' => 'M1', 'channel_id' => 'C1', 'body' => 'we are slipping to next week' }
        )
        UpdatedHandler.call(update_delivery, @integration)

        assert_equal 'we are slipping to next week', @cache.reload.body
        assert_equal original_snapshot, decision.reload.body_snapshot
      end

      test 'pin for unknown message_id is a logged no-op' do
        delivery = build_delivery(basic_payload('message_id' => 'unknown'))

        assert_no_difference -> { Decision.count } do
          assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
            assert_nothing_raised { PinnedHandler.call(delivery, @integration) }
          end
        end
      end

      test 'missing message_id is logged and does not raise' do
        delivery = build_delivery(basic_payload.except('message_id'))

        assert_no_difference -> { Decision.count } do
          assert_nothing_raised { PinnedHandler.call(delivery, @integration) }
        end
      end

      test 'repinning an unpinned decision reactivates it without changing body_snapshot' do
        PinnedHandler.call(build_delivery(basic_payload), @integration)
        decision = Decision.find_by!(hourglass_message_id: 'M1')
        decision.update!(unpinned_at: 5.minutes.ago)
        @cache.update!(body: 'body changed after first pin')
        original_snapshot = decision.body_snapshot

        repin_payload = basic_payload('pinned_at' => '2026-05-02T11:00:00Z')
        PinnedHandler.call(build_delivery(repin_payload), @integration)

        decision.reload
        assert_nil decision.unpinned_at
        assert_equal original_snapshot, decision.body_snapshot
      end
    end
  end
end
