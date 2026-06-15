require 'test_helper'
require 'webmock/minitest'

module HourglassWebhookProcessor
  module Message
    class UpdatedHandlerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        stub_request(:get, %r{https://hg\.test/api/v1/users/lookup}).to_return(status: 404, body: '{}')
        @user = User.create!(name: 'UH', email: 'updated_handler@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'WS', owner: @user)
        @team = @workspace.teams.create!(name: 'T', identifier: 'UDH')
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
          body: 'original',
          posted_at: 1.minute.ago,
          source: 'webhook'
        )
      end

      def build_delivery(payload, event: 'message.updated')
        WebhookDelivery.create!(
          source: 'hourglass', delivery_id: SecureRandom.uuid,
          event_type: event, received_at: Time.current, payload: payload
        )
      end

      test 'updates existing cache and broadcasts replace' do
        delivery = build_delivery(
          { 'message_id' => 'M1', 'channel_id' => 'C1', 'body' => 'edited!' }
        )

        assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
          UpdatedHandler.call(delivery, @integration)
        end

        assert_equal 'edited!', @cache.reload.body
        assert_not_nil @cache.edited_at
      end

      test 'falls through to CreatedHandler when cache missing' do
        delivery = build_delivery({
                                    'message_id' => 'M_missing', 'channel_id' => 'C1', 'body' => 'first sight',
                                    'posted_at' => Time.current.iso8601,
                                    'author' => { 'email' => @user.email }
                                  })

        assert_difference -> { HourglassMessageCache.count }, 1 do
          UpdatedHandler.call(delivery, @integration)
        end
      end

      test 'loop guard skips when comment owns message_id' do
        @project.comments.create!(
          user: @user, body: 'pushed', pushed_to_hourglass_message_id: 'M1'
        )
        delivery = build_delivery({ 'message_id' => 'M1', 'channel_id' => 'C1', 'body' => 'should not apply' })

        assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
          UpdatedHandler.call(delivery, @integration)
        end
        assert_equal 'original', @cache.reload.body
      end
    end
  end
end
