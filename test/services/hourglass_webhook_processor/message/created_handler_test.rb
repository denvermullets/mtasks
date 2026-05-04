require 'test_helper'

module HourglassWebhookProcessor
  module Message
    class CreatedHandlerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @user = User.create!(name: 'CH', email: 'created_handler@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'CRH')
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
          hourglass_channel_name: 'general',
          hourglass_integration: @integration,
          created_by_user: @user,
          status: 'active'
        )
      end

      def build_delivery(payload, event: 'message.created')
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
          'body' => 'hello world',
          'posted_at' => '2026-05-01T10:00:00Z',
          'author' => { 'email' => @user.email, 'display_name' => 'CH', 'user_id' => 'hu_1' }
        }.merge(overrides)
      end

      test 'happy path persists cache and enqueues append broadcast' do
        delivery = build_delivery(basic_payload)

        assert_difference -> { HourglassMessageCache.count }, 1 do
          assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
            CreatedHandler.call(delivery, @integration)
          end
        end

        cache = HourglassMessageCache.find_by(hourglass_message_id: 'M1')
        assert_equal 'hello world', cache.body
        assert_equal 'C1', cache.hourglass_channel_id
        assert_equal 'webhook', cache.source
      end

      test 'replay broadcasts replace and does not duplicate' do
        delivery1 = build_delivery(basic_payload)
        CreatedHandler.call(delivery1, @integration)

        delivery2 = build_delivery(basic_payload('body' => 'updated body'))

        assert_no_difference -> { HourglassMessageCache.count } do
          assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
            CreatedHandler.call(delivery2, @integration)
          end
        end
      end

      test 'loop guard skips cache + broadcast when comment owns the message_id' do
        comment = @project.comments.create!(
          user: @user,
          body: 'native push',
          pushed_to_hourglass_message_id: 'M1'
        )
        delivery = build_delivery(basic_payload)

        assert_no_difference -> { HourglassMessageCache.count } do
          assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
            CreatedHandler.call(delivery, @integration)
          end
        end

        assert_not_nil comment.reload.pushed_to_hourglass_at
      end

      test 'no link results in no cache + no broadcast' do
        delivery = build_delivery(basic_payload('channel_id' => 'unknown_channel'))

        assert_no_difference -> { HourglassMessageCache.count } do
          assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
            CreatedHandler.call(delivery, @integration)
          end
        end
      end

      test 'echo loop guard skips cache + broadcast when an echo row exists for message_id' do
        HourglassMessageCache.create!(
          hourglass_message_id: 'M1',
          hourglass_channel_id: 'C1',
          body: 'echoed outbound',
          message_type: 'system',
          posted_at: Time.current,
          source: 'echo'
        )
        delivery = build_delivery(basic_payload)

        assert_no_difference -> { HourglassMessageCache.count } do
          assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
            CreatedHandler.call(delivery, @integration)
          end
        end

        assert_equal 'echo', HourglassMessageCache.find_by(hourglass_message_id: 'M1').source
      end

      test 'missing message_id is logged and does not raise' do
        delivery = build_delivery(basic_payload.except('message_id'))

        assert_no_difference -> { HourglassMessageCache.count } do
          assert_nothing_raised { CreatedHandler.call(delivery, @integration) }
        end
      end
    end
  end
end
