require 'test_helper'

module Discussion
  class CommentsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(name: 'Composer Carol', email: 'composer@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @user)
      @team = @workspace.teams.create!(name: 'T', identifier: 'DCC')
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

      def initialize(response: nil, raise_error: nil)
        @response = response
        @raise_error = raise_error
        @calls = []
      end

      def post_channel_message(channel_id, body:, message_type: nil, idempotency_key: nil)
        @calls << { channel_id: channel_id, body: body, message_type: message_type, idempotency_key: idempotency_key }
        raise @raise_error if @raise_error

        @response
      end
    end

    test 'create with toggle off creates a JAIT-native comment only and does not push' do
      raise_client = StubClient.new(raise_error: RuntimeError.new('should not call'))

      with_stubbed_client(raise_client) do
        assert_difference -> { @project.comments.count }, 1 do
          post team_project_discussion_comments_path(@team, @project),
               params: { comment: { body: 'no chat please' }, also_send_to_chat: '0' },
               as: :turbo_stream
        end
      end

      assert_response :success
      assert_empty raise_client.calls
      assert_nil @project.comments.last.pushed_to_hourglass_message_id
    end

    test 'create with toggle on creates the comment and pushes to chat' do
      client = StubClient.new(response: { 'id' => 'm_99' })

      with_stubbed_client(client) do
        assert_difference -> { @project.comments.count }, 1 do
          post team_project_discussion_comments_path(@team, @project),
               params: { comment: { body: 'send it' }, also_send_to_chat: '1' },
               as: :turbo_stream
        end
      end

      assert_response :success
      comment = @project.comments.last
      assert_equal 'm_99', comment.pushed_to_hourglass_message_id
      assert_not_nil comment.pushed_to_hourglass_at
      assert_equal 1, client.calls.size
      assert_equal "comment-#{comment.id}-push", client.calls.first[:idempotency_key]
    end

    test 'push action retroactively pushes an existing comment and stamps it' do
      comment = @project.comments.create!(user: @user, body: 'retroactive')
      client = StubClient.new(response: { 'id' => 'm_retro' })

      with_stubbed_client(client) do
        post push_team_project_discussion_comment_path(@team, @project, comment),
             as: :turbo_stream
      end

      assert_response :success
      comment.reload
      assert_equal 'm_retro', comment.pushed_to_hourglass_message_id
      assert_not_nil comment.pushed_to_hourglass_at
    end

    test 'push action surfaces error when API fails and does not stamp' do
      comment = @project.comments.create!(user: @user, body: 'will fail')
      client = StubClient.new(raise_error: Hourglass::ApiClient::Error.new('nope'))

      with_stubbed_client(client) do
        post push_team_project_discussion_comment_path(@team, @project, comment),
             as: :turbo_stream
      end

      assert_response :success
      assert_includes response.body, 'nope'
      assert_nil comment.reload.pushed_to_hourglass_message_id
    end
  end
end
