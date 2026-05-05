require 'test_helper'

module Discussion
  class IssueCommentsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(name: 'IC', email: 'issue_comments@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @user)
      @team = @workspace.teams.create!(name: 'T', identifier: 'ICC')
      @team.team_memberships.create!(user: @user)
      @lane = @team.lanes.create!(name: 'L', position: 0)
      @issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
      @integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
        webhook_secret: 'wh', connected_by_user: @user
      )
      @thread_link = @team.hourglass_links.create!(
        link_type: 'issue_thread',
        mtasks_issue: @issue,
        mtasks_issue_identifier: @issue.identifier,
        hourglass_thread_id: 'T_42',
        hourglass_integration: @integration,
        created_by_user: @user
      )
      sign_in_as(@user)
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

      def initialize(response: nil)
        @response = response
        @calls = []
      end

      def post_thread_message(thread_id, body:, message_type: nil, idempotency_key: nil)
        @calls << { thread_id: thread_id, body: body, message_type: message_type, idempotency_key: idempotency_key }
        @response
      end

      def post_channel_message(*)
        raise 'should not call channel for issue thread'
      end
    end

    test 'create with toggle off creates an issue-scoped Comment and skips push' do
      raise_client = StubClient.new(response: { 'id' => 'unused' })

      with_stubbed_client(raise_client) do
        assert_difference -> { @issue.comments.count }, 1 do
          post team_issue_discussion_comments_path(@team, @issue),
               params: { comment: { body: 'jait only' }, also_send_to_chat: '0' },
               as: :turbo_stream
        end
      end

      assert_response :success
      assert_empty raise_client.calls
      comment = @issue.comments.last
      assert_nil comment.pushed_to_hourglass_message_id
      assert_nil comment.project_id
    end

    test 'create with toggle on pushes to the linked thread' do
      client = StubClient.new(response: { 'id' => 'm_thread' })

      with_stubbed_client(client) do
        assert_difference -> { @issue.comments.count }, 1 do
          post team_issue_discussion_comments_path(@team, @issue),
               params: { comment: { body: 'send to thread' }, also_send_to_chat: '1' },
               as: :turbo_stream
        end
      end

      assert_response :success
      assert_equal 1, client.calls.size
      assert_equal 'T_42', client.calls.first[:thread_id]
      comment = @issue.comments.last
      assert_equal 'm_thread', comment.pushed_to_hourglass_message_id
      assert_equal "comment-#{comment.id}-push", client.calls.first[:idempotency_key]
    end
  end
end
