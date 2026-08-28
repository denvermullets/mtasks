require 'test_helper'
require 'webmock/minitest'

# VEK-585: the server surface the browser cannot see — inbound webhook deliveries, and the
# outbound API calls the integrations make.
#
# What this file guarantees, beyond one case per call site: that a provider redelivery produces
# the same event_id (so vanalytics dedupes it), that one delivery acting on several records
# produces *different* ones (so vanalytics does not eat all but the first), and that nothing a
# user typed — PR title, branch, repo name, pinned message body — reaches properties.
module Vektis
  class IntegrationTrackingTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include VektisEventTestHelper

    DELIVERY = 'delivery-guid-1'.freeze

    setup do
      @user = User.create!(name: 'Int User', email: "int_#{SecureRandom.hex(4)}@example.com",
                           password: 'password')
      @workspace = Workspace.create!(name: 'Int WS', owner: @user)
      @team = @workspace.teams.create!(name: 'Int Team', identifier: 'INT')
      @team.team_memberships.create!(user: @user)
      enable_vektis!(@team)
      @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
      @done = @team.lanes.create!(name: 'done', position: 1)
      @project = @team.projects.create!(name: 'Int Project')
      clear_enqueued_jobs
    end

    def issue(title: 'Tracked issue', number: 1)
      Issue.create!(title: title, team: @team, lane: @backlog, creator: @user, team_number: number)
    end

    # --- Hourglass --------------------------------------------------------------------------------

    def hourglass_integration
      @workspace.hourglass_integrations.create!(
        hourglass_server_id: "srv_#{SecureRandom.hex(4)}", base_url: 'https://hg.test',
        api_token: 'tok', webhook_secret: 'wh', connected_by_user: @user
      )
    end

    def message_cache(body: 'we ship on Friday')
      HourglassMessageCache.create!(hourglass_message_id: 'M1', hourglass_channel_id: 'C1',
                                    source: 'webhook', posted_at: 1.hour.ago, body: body)
    end

    def channel_link(integration)
      @team.hourglass_links.create!(link_type: 'project_channel', mtasks_project: @project,
                                    hourglass_channel_id: 'C1', hourglass_channel_name: 'general',
                                    hourglass_integration: integration, created_by_user: @user,
                                    status: 'active')
    end

    def hourglass_delivery(event_type, payload, delivery_id: DELIVERY)
      WebhookDelivery.create!(source: 'hourglass', delivery_id: delivery_id, event_type: event_type,
                              received_at: Time.current, payload: payload)
    end

    # HourglassIntegration belongs to a workspace and serves every team in it, so the delivery-level
    # sync has no tenant of its own — it borrows the team of whichever record the handler touched.
    test 'a processed hourglass delivery emits hourglass-integration/sync under the touched team' do
      integration = hourglass_integration
      channel_link(integration)
      message_cache
      delivery = hourglass_delivery('message.pinned', { 'message_id' => 'M1', 'channel_id' => 'C1' })

      HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)

      assert_emitted 'hourglass-integration', 'sync'
      event = event_for('hourglass-integration', 'sync')
      assert_equal 'message.pinned', event['properties']['webhook_event']
      assert_equal 'webhook', event['properties']['via']
      assert_equal [@team.id], emitted_team_ids.uniq
      emitted.each { |e| assert_taxonomy_conformant(e) }
    end

    # No team-scoped record was touched, so there is no tenant to bill the delivery to. Guessing one
    # would file this workspace's activity under an arbitrary team's VEKTIS account.
    test 'a delivery that touches no team-scoped record emits nothing' do
      integration = hourglass_integration
      delivery = hourglass_delivery('message.created', { 'message_id' => 'm1', 'channel_id' => 'C1' })

      HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)

      assert_empty emitted
      assert_not_nil delivery.reload.processed_at, 'the delivery is still processed'
    end

    test 'a received-but-unhandled delivery emits nothing' do
      integration = hourglass_integration
      delivery = hourglass_delivery('ping', {})

      HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)

      assert_empty emitted, 'a ping is received, not processed'
      assert_not_nil delivery.reload.processed_at
    end

    test 'a handler that raises does not emit a sync' do
      integration = hourglass_integration
      delivery = hourglass_delivery('message.created', { 'message_id' => 'm1', 'channel_id' => 'C1' })

      with_stubbed_class_method(HourglassWebhookProcessor::Message::CreatedHandler, :call,
                                ->(*) { raise 'boom' }) do
        HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)
      end

      refute_emitted 'hourglass-integration', 'sync'
    end

    # What is under test is purely the event_id derivation: the same delivery guid must produce the
    # same id, so that a redelivery vanalytics has already seen dedupes instead of double counting.
    # The delivery row and the decision are both cleared between runs to get past the app's own two
    # guards — WebhookDelivery#processed_at and the handler's existing-decision check — because with
    # either in place the handler correctly does nothing the second time and there is no second
    # event to compare.
    test 'reprocessing the same delivery id reproduces the same sync event_id' do
      integration = hourglass_integration
      channel_link(integration)
      message_cache
      payload = { 'message_id' => 'M1', 'channel_id' => 'C1' }

      HourglassWebhookProcessorJob.perform_now(integration.id, hourglass_delivery('message.pinned', payload).id)
      first = event_for('hourglass-integration', 'sync')['event_id']
      clear_enqueued_jobs
      WebhookDelivery.delete_all
      Decision.delete_all
      HourglassWebhookProcessorJob.perform_now(integration.id, hourglass_delivery('message.pinned', payload).id)

      assert_not_nil first
      assert_equal first, event_for('hourglass-integration', 'sync')['event_id']
    end

    test 'pinning a message emits decision/create without the message body' do
      integration = hourglass_integration
      channel_link(integration)
      cache = message_cache(body: 'we ship the credentials rotation on Friday')
      delivery = hourglass_delivery('message.pinned', { 'message_id' => 'M1', 'channel_id' => 'C1' })

      HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)

      assert_emitted 'decision', 'create'
      assert_equal 'project', event_for('decision', 'create')['properties']['entity']
      assert_no_user_content cache.body, 'general'
      emitted.each { |e| assert_taxonomy_conformant(e) }
    end

    test 'unpinning a decision emits decision/delete' do
      integration = hourglass_integration
      link = channel_link(integration)
      message_cache
      Decision.create!(team: @team, project: link.mtasks_project, hourglass_message_id: 'M1',
                       pinned_at: 1.hour.ago, body_snapshot: 'we ship on Friday',
                       idempotency_key: "pin:M1:#{1.hour.ago.utc.iso8601}")
      delivery = hourglass_delivery('message.unpinned', { 'message_id' => 'M1', 'channel_id' => 'C1' })

      HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)

      assert_emitted 'decision', 'delete'
    end

    test 'an inbound link.created emits hourglass-integration/link with the entity' do
      integration = hourglass_integration
      delivery = hourglass_delivery('link.created', {
                                      'data' => { 'link_type' => 'project_channel',
                                                  'mtasks_project_id' => @project.id,
                                                  'hourglass_channel_id' => 'C9',
                                                  'hourglass_channel_name' => 'launch-room' }
                                    })

      HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)

      assert_emitted 'hourglass-integration', 'link'
      assert_equal 'project', event_for('hourglass-integration', 'link')['properties']['entity']
      assert_no_user_content 'launch-room', @project.name
    end

    test 'an inbound link.removed emits hourglass-integration/unlink' do
      integration = hourglass_integration
      channel_link(integration)
      delivery = hourglass_delivery('link.removed', {
                                      'data' => { 'link_type' => 'project_channel',
                                                  'hourglass_channel_id' => 'C1' }
                                    })

      HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)

      assert_emitted 'hourglass-integration', 'unlink'
      assert_equal 'project', event_for('hourglass-integration', 'unlink')['properties']['entity']
    end

    test 'outbound emission to Hourglass emits sync keyed on the job idempotency key' do
      integration = hourglass_integration
      channel_link(integration)
      tracked = issue
      tracked.update!(project: @project)
      clear_enqueued_jobs
      stub_request(:post, %r{https://hg\.test/api/v1/channels/C1/messages})
        .to_return(status: 200, body: { id: 'msg1', channel_id: 'C1' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      HourglassOutboundEmitterJob.perform_now(event_type: 'issue.created', issue_id: tracked.id,
                                              actor_id: @user.id)

      event = event_for('hourglass-integration', 'sync')
      assert_not_nil event
      assert_equal 'job', event['properties']['via']
      assert_no_user_content tracked.title
    end
  end
end
