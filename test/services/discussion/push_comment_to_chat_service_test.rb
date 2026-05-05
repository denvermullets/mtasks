require 'test_helper'

module Discussion
  class PushCommentToChatServiceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: 'Pat', email: 'push@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @user)
      @team = @workspace.teams.create!(name: 'T', identifier: 'PCS')
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
        created_by_user: @user
      )
    end

    def with_stubbed_client(client)
      Hourglass::ApiClient.singleton_class.alias_method(:_orig_for_integration, :for_integration)
      Hourglass::ApiClient.define_singleton_method(:for_integration) { |_| client }
      yield
    ensure
      Hourglass::ApiClient.singleton_class.alias_method(:for_integration, :_orig_for_integration)
      Hourglass::ApiClient.singleton_class.send(:remove_method, :_orig_for_integration)
    end

    class StubClient
      attr_reader :calls

      def initialize(response: nil, raise_error: nil)
        @response = response
        @raise_error = raise_error
        @calls = []
      end

      def post_channel_message(channel_id, body:, message_type: nil, idempotency_key: nil)
        @calls << { kind: :channel, channel_id: channel_id, body: body, message_type: message_type,
                    idempotency_key: idempotency_key }
        raise @raise_error if @raise_error

        @response
      end

      def post_thread_message(thread_id, body:, message_type: nil, idempotency_key: nil)
        @calls << { kind: :thread, thread_id: thread_id, body: body, message_type: message_type,
                    idempotency_key: idempotency_key }
        raise @raise_error if @raise_error

        @response
      end
    end

    test 'success stamps pushed_to_hourglass_message_id and pushed_to_hourglass_at' do
      client = StubClient.new(response: { 'id' => 'm_42' })
      comment = @project.comments.create!(user: @user, body: 'hello world')

      result = with_stubbed_client(client) { PushCommentToChatService.call(comment: comment) }

      assert result.success?
      assert_equal 'general', result.channel_name
      comment.reload
      assert_equal 'm_42', comment.pushed_to_hourglass_message_id
      assert_not_nil comment.pushed_to_hourglass_at

      call = client.calls.first
      assert_equal 'C1', call[:channel_id]
      assert_equal 'system', call[:message_type]
      assert_equal "comment-#{comment.id}-push", call[:idempotency_key]
      assert_includes call[:body], 'said in JAIT:'
    end

    test 'idempotent re-push when already pushed returns success without calling API' do
      client = StubClient.new(response: { 'id' => 'should_not_call' })
      comment = @project.comments.create!(
        user: @user, body: 'hi',
        pushed_to_hourglass_message_id: 'm_old',
        pushed_to_hourglass_at: 1.minute.ago
      )

      result = with_stubbed_client(client) { PushCommentToChatService.call(comment: comment) }
      assert result.success?
      assert_empty client.calls
      assert_equal 'm_old', comment.reload.pushed_to_hourglass_message_id
    end

    test 'returns failure when no active hourglass link exists' do
      no_link_project = @team.projects.create!(name: 'No Link')
      comment = no_link_project.comments.create!(user: @user, body: 'orphan')

      result = PushCommentToChatService.call(comment: comment)
      assert_not result.success?
      assert_match(/no active hourglass link/i, result.error)
      assert_nil comment.reload.pushed_to_hourglass_message_id
    end

    test 'with explicit issue_thread link posts via post_thread_message' do
      lane = @team.lanes.create!(name: 'Backlog', position: 0)
      issue = @team.issues.create!(title: 'I', creator: @user, lane: lane)
      thread_link = @team.hourglass_links.create!(
        link_type: 'issue_thread',
        mtasks_issue: issue,
        mtasks_issue_identifier: issue.identifier,
        hourglass_thread_id: 'T_42',
        hourglass_integration: @integration,
        created_by_user: @user
      )
      comment = issue.comments.create!(user: @user, body: 'thread reply')
      client = StubClient.new(response: { 'id' => 'm_thread' })

      result = with_stubbed_client(client) { PushCommentToChatService.call(comment: comment, link: thread_link) }

      assert result.success?
      call = client.calls.first
      assert_equal :thread, call[:kind]
      assert_equal 'T_42', call[:thread_id]
      assert_equal "comment-#{comment.id}-push", call[:idempotency_key]
      assert_equal 'm_thread', comment.reload.pushed_to_hourglass_message_id
    end

    test 'API failure does not stamp the comment and returns the error' do
      client = StubClient.new(raise_error: Hourglass::ApiClient::Error.new('boom'))
      comment = @project.comments.create!(user: @user, body: 'hi')

      result = with_stubbed_client(client) { PushCommentToChatService.call(comment: comment) }
      assert_not result.success?
      assert_equal 'boom', result.error
      assert_nil comment.reload.pushed_to_hourglass_message_id
      assert_nil comment.pushed_to_hourglass_at
    end
  end
end
