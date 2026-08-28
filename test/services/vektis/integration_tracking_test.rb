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
      enable_vektis!
      @user = User.create!(name: 'Int User', email: "int_#{SecureRandom.hex(4)}@example.com",
                           password: 'password')
      @workspace = Workspace.create!(name: 'Int WS', owner: @user)
      @team = @workspace.teams.create!(name: 'Int Team', identifier: 'INT')
      @team.team_memberships.create!(user: @user)
      @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
      @done = @team.lanes.create!(name: 'done', position: 1)
      @project = @team.projects.create!(name: 'Int Project')
      clear_enqueued_jobs
    end

    teardown { restore_vektis_env! }

    # --- GitHub -----------------------------------------------------------------------------------

    def github_subscription
      installation = GithubInstallation.create!(installation_id: "inst_#{SecureRandom.hex(4)}",
                                                workspace: @workspace)
      GithubRepositorySubscription.create!(team: @team, github_installation: installation,
                                           github_repo_full_name: 'acme/secret-repo')
    end

    def pr_data(number: 1, merged: false, state: 'open', title: 'Fix INT-1 auth bug',
                head_ref: 'feature/int-1-auth')
      {
        'number' => number, 'title' => title, 'body' => 'closes INT-1',
        'html_url' => "https://github.com/acme/secret-repo/pull/#{number}",
        'state' => state, 'user' => { 'login' => 'octocat' },
        'head' => { 'ref' => head_ref }, 'base' => { 'ref' => 'main' },
        'merged' => merged, 'merged_at' => merged ? Time.current.iso8601 : nil
      }
    end

    def issue(title: 'Tracked issue', number: 1)
      Issue.create!(title: title, team: @team, lane: @backlog, creator: @user, team_number: number)
    end

    test 'a processed pull_request delivery emits github-integration/sync with the provider event' do
      subscription = github_subscription
      issue

      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data.to_json, 'opened', DELIVERY)

      assert_emitted 'github-integration', 'sync'
      event = event_for('github-integration', 'sync')
      assert_equal 'pull_request.opened', event['properties']['webhook_event']
      assert_equal 'webhook', event['properties']['via']
      assert_equal 'github', event['properties']['provider']
      assert_nil event['user_id'], 'a signature-authenticated delivery has no user'
      emitted.each { |e| assert_taxonomy_conformant(e) }
    end

    test 'a merged pull_request is separated from a closed one' do
      subscription = github_subscription

      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data(merged: true, state: 'closed').to_json,
                                            'closed', DELIVERY)

      assert_equal 'pull_request.merged', event_for('github-integration', 'sync')['properties']['webhook_event']
    end

    # VEK-587: `action` originates in the GitHub payload and perform is public, so the allowlist has
    # to live at the emit point too — not only in Webhooks::GithubController#processable_action?.
    test 'an action outside the allowlist drops the property rather than interpolating the payload' do
      subscription = github_subscription

      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data.to_json,
                                            'assigned"><script>', DELIVERY)

      assert_emitted 'github-integration', 'sync'
      event = event_for('github-integration', 'sync')
      assert_not_includes event['properties'].keys, 'webhook_event'
      assert_no_match(/script/, event.to_json, 'no raw payload text may reach the wire')
    end

    test 'the emit-point allowlist matches the deliveries the controller actually admits' do
      assert_equal Webhooks::GithubController::PROCESSABLE_ACTIONS.sort,
                   GithubWebhookProcessorJob::PR_WEBHOOK_ACTIONS.sort,
                   'the job must not widen or narrow what the webhook controller lets through'
    end

    test 'attaching issues to a PR emits one link event carrying the count' do
      subscription = github_subscription
      issue(title: 'First', number: 1)
      issue(title: 'Second', number: 2)

      GithubWebhookProcessorJob.perform_now(
        subscription.id, pr_data(title: 'Fix INT-1 and INT-2').to_json, 'opened', DELIVERY
      )

      links = events_for('github-integration', 'link')
      assert_equal 1, links.size, 'two issues on one PR is one linking gesture'
      assert_equal 2, links.first['properties']['count']
      assert_equal 'issue', links.first['properties']['entity']
    end

    test 'PR automation completing an issue emits issue-workflow and github-integration/complete' do
      subscription = github_subscription
      tracked = issue
      subscription.pr_automation_rules.create!(trigger: 'pr_merged', lane: @done, branch_pattern: 'main')

      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data(merged: true, state: 'closed').to_json,
                                            'closed', DELIVERY)

      assert_equal @done, tracked.reload.lane
      assert_emitted 'issue-workflow', 'complete'
      assert_emitted 'github-integration', 'complete'
      workflow = event_for('issue-workflow', 'complete')
      assert_equal 'webhook', workflow['properties']['via']
      assert_equal 0, workflow['properties']['from_position']
      assert_equal 1, workflow['properties']['to_position']
      assert_equal 'forward', workflow['properties']['direction']
    end

    test 'one delivery completing two issues produces two distinct event_ids' do
      subscription = github_subscription
      issue(title: 'First', number: 1)
      issue(title: 'Second', number: 2)
      subscription.pr_automation_rules.create!(trigger: 'pr_merged', lane: @done, branch_pattern: 'main')

      GithubWebhookProcessorJob.perform_now(
        subscription.id, pr_data(title: 'Fix INT-1 and INT-2', merged: true, state: 'closed').to_json,
        'closed', DELIVERY
      )

      completions = events_for('issue-workflow', 'complete')
      assert_equal 2, completions.size
      assert_equal 2, completions.map { |event| event['event_id'] }.uniq.size,
                   'a scalar idempotency key would collapse these onto one row at vanalytics'
    end

    test 'redelivering the same guid reproduces the same event_ids' do
      subscription = github_subscription
      issue

      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data.to_json, 'opened', DELIVERY)
      first = event_for('github-integration', 'sync')['event_id']
      clear_enqueued_jobs
      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data.to_json, 'opened', DELIVERY)

      assert_equal first, event_for('github-integration', 'sync')['event_id']
    end

    test 'a delivery with no guid still emits, with a random event_id rather than a partial key' do
      subscription = github_subscription
      issue

      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data.to_json, 'opened', nil)

      assert_emitted 'github-integration', 'sync'
      first = event_for('github-integration', 'sync')['event_id']
      clear_enqueued_jobs
      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data.to_json, 'opened', nil)
      assert_not_equal first, event_for('github-integration', 'sync')['event_id']
    end

    test 'no GitHub payload content reaches properties' do
      subscription = github_subscription
      tracked = issue(title: 'Rotate the production signing key')
      subscription.pr_automation_rules.create!(trigger: 'pr_merged', lane: @done, branch_pattern: 'main')

      GithubWebhookProcessorJob.perform_now(subscription.id, pr_data(merged: true, state: 'closed').to_json,
                                            'closed', DELIVERY)

      # Autoincrement ids are deliberately not on this list: assert_no_user_content is a substring
      # check, and a single-digit id matches the legitimate "count":1 in a sibling event.
      assert_no_user_content 'Fix INT-1 auth bug', 'feature/int-1-auth', 'acme/secret-repo',
                             'octocat', tracked.title, @done.name
    end

    # A dead queue is the most likely analytics fault at a webhook boundary, and the one with the
    # worst blast radius: GitHub retries on non-2xx, so a raise here would become a redelivery storm.
    test 'an analytics fault never fails webhook processing' do
      subscription = github_subscription
      issue

      with_stubbed_class_method(VektisEventJob, :perform_later, ->(*) { raise 'queue is down' }) do
        assert_nothing_raised do
          GithubWebhookProcessorJob.perform_now(subscription.id, pr_data.to_json, 'opened', DELIVERY)
        end
      end

      assert_equal 1, subscription.pull_requests.count, 'the sync itself still committed'
    end

    test 'posting a PR comment emits github-integration/sync from the job path' do
      subscription = github_subscription
      tracked = issue
      pull_request = subscription.pull_requests.create!(pr_number: 9, title: 'PR', html_url: 'https://x',
                                                        state: 'open', author_login: 'octocat',
                                                        head_ref: 'main', base_ref: 'main')
      issue_pr = IssuePullRequest.create!(issue: tracked, pull_request: pull_request)

      client = stub_github_client
      with_stubbed_class_method(GithubApiClient, :new, ->(*) { client }) do
        GithubCommentPosterJob.perform_now(issue_pr.id)
      end

      event = event_for('github-integration', 'sync')
      assert_not_nil event
      assert_equal 'job', event['properties']['via']
      assert_no_user_content tracked.title, 'acme/secret-repo'
    end

    def stub_github_client
      client = Object.new
      client.define_singleton_method(:post_pr_comment) { |*| true }
      client
    end

    # --- Hourglass --------------------------------------------------------------------------------

    def hourglass_integration
      @workspace.hourglass_integrations.create!(
        hourglass_server_id: "srv_#{SecureRandom.hex(4)}", base_url: 'https://hg.test',
        api_token: 'tok', webhook_secret: 'wh', connected_by_user: @user
      )
    end

    def hourglass_delivery(event_type, payload, delivery_id: DELIVERY)
      WebhookDelivery.create!(source: 'hourglass', delivery_id: delivery_id, event_type: event_type,
                              received_at: Time.current, payload: payload)
    end

    test 'a processed hourglass delivery emits hourglass-integration/sync' do
      integration = hourglass_integration
      delivery = hourglass_delivery('message.created', { 'message_id' => 'm1', 'channel_id' => 'C1' })

      HourglassWebhookProcessorJob.perform_now(integration.id, delivery.id)

      assert_emitted 'hourglass-integration', 'sync'
      event = event_for('hourglass-integration', 'sync')
      assert_equal 'message.created', event['properties']['webhook_event']
      assert_equal 'webhook', event['properties']['via']
      emitted.each { |e| assert_taxonomy_conformant(e) }
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

    test 'reprocessing the same delivery id reproduces the same sync event_id' do
      integration = hourglass_integration
      payload = { 'message_id' => 'm1', 'channel_id' => 'C1' }

      HourglassWebhookProcessorJob.perform_now(integration.id, hourglass_delivery('message.created', payload).id)
      first = event_for('hourglass-integration', 'sync')['event_id']
      clear_enqueued_jobs
      WebhookDelivery.delete_all
      HourglassWebhookProcessorJob.perform_now(integration.id, hourglass_delivery('message.created', payload).id)

      assert_equal first, event_for('hourglass-integration', 'sync')['event_id']
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
