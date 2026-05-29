require 'test_helper'

class HourglassOutboundEmitterJobTest < ActiveJob::TestCase
  def with_stubbed_client(client)
    Hourglass::ApiClient.singleton_class.alias_method(:_orig_for_integration, :for_integration)
    Hourglass::ApiClient.define_singleton_method(:for_integration) { |_| client }
    yield
  ensure
    Hourglass::ApiClient.singleton_class.alias_method(:for_integration, :_orig_for_integration)
    Hourglass::ApiClient.singleton_class.send(:remove_method, :_orig_for_integration)
  end

  def fake_client(message_id: 'M_OUT', channel_id: 'C1', captured: {}, raise_with: nil)
    fake = Object.new
    %i[post_channel_message post_thread_message].each do |m|
      fake.define_singleton_method(m) do |target, **kwargs|
        captured[:method] = m
        captured[:target] = target
        captured.merge!(kwargs)
        raise raise_with if raise_with

        { 'id' => message_id, 'channel_id' => channel_id }
      end
    end
    fake.define_singleton_method(:respond_to_missing?) { |*| true }
    fake
  end

  setup do
    seed_workspace
    seed_links
  end

  def seed_workspace
    @user = User.create!(name: 'Ryan', email: 'ryan_emitter@example.com', password: 'password')
    @other = User.create!(name: 'Sam', email: 'sam_emitter@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'EMT')
    @team.team_memberships.create!(user: @user)
    @project = @team.projects.create!(name: 'Proj')
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @in_progress = @team.lanes.create!(name: 'In Progress', position: 1)
    @issue = @team.issues.create!(title: 'Ship it', lane: @backlog, project: @project, creator: @user)
  end

  def seed_links
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
      webhook_secret: 'wh', connected_by_user: @user
    )
    @channel_link = @team.hourglass_links.create!(
      link_type: 'project_channel', mtasks_project: @project, hourglass_channel_id: 'C1',
      hourglass_channel_name: 'general', hourglass_integration: @integration, created_by_user: @user
    )
    @thread_link = @team.hourglass_links.create!(
      link_type: 'issue_thread', mtasks_issue: @issue, hourglass_thread_id: 'T1',
      hourglass_integration: @integration, created_by_user: @user
    )
  end

  def build_version(changes)
    PaperTrail::Version.create!(
      item_type: 'Issue', item_id: @issue.id, event: 'update', object_changes: changes,
      created_at: Time.current
    )
  end

  test 'issue.created posts to project channel and writes echo cache' do
    captured = {}
    with_stubbed_client(fake_client(captured: captured)) do
      assert_difference -> { HourglassMessageCache.where(source: 'echo').count }, 1 do
        HourglassOutboundEmitterJob.perform_now(
          event_type: 'issue.created', issue_id: @issue.id, actor_id: @user.id
        )
      end
    end

    assert_equal :post_channel_message, captured[:method]
    assert_equal 'C1', captured[:target]
    assert_equal 'system', captured[:message_type]
    assert_match(/created by Ryan: Ship it/, captured[:body])
    assert_match(/^issue-#{@issue.id}-issue.created-create$/, captured[:idempotency_key])
    assert_kind_of Hash, captured[:data]
    assert_equal 'issue.created', captured[:data][:event_type]
    assert_equal @issue.identifier, captured[:data][:identifier]
    assert_equal 'Ship it', captured[:data][:title]

    echo = HourglassMessageCache.find_by(hourglass_message_id: 'M_OUT')
    assert_equal 'echo', echo.source
    assert_equal 'C1', echo.hourglass_channel_id
  end

  test 'issue.status_changed posts to thread when issue_thread link exists' do
    version = build_version('lane_id' => [@backlog.id, @in_progress.id])
    captured = {}

    with_stubbed_client(fake_client(captured: captured)) do
      HourglassOutboundEmitterJob.perform_now(
        event_type: 'issue.status_changed', issue_id: @issue.id, actor_id: @user.id, version_id: version.id
      )
    end

    assert_equal :post_thread_message, captured[:method]
    assert_equal 'T1', captured[:target]
    assert_match(/moved Backlog → In Progress by Ryan/, captured[:body])
  end

  test 'issue.status_changed without issue_thread link falls back to project channel' do
    @thread_link.destroy
    version = build_version('lane_id' => [@backlog.id, @in_progress.id])
    captured = {}

    with_stubbed_client(fake_client(captured: captured)) do
      HourglassOutboundEmitterJob.perform_now(
        event_type: 'issue.status_changed', issue_id: @issue.id, actor_id: @user.id, version_id: version.id
      )
    end

    assert_equal :post_channel_message, captured[:method]
    assert_equal 'C1', captured[:target]
    assert_match(/moved Backlog → In Progress by Ryan/, captured[:body])
  end

  test 'issue.status_changed with no usable link is a silent no-op' do
    @thread_link.destroy
    @channel_link.destroy
    version = build_version('lane_id' => [@backlog.id, @in_progress.id])
    captured = {}

    with_stubbed_client(fake_client(captured: captured)) do
      assert_no_difference -> { HourglassMessageCache.count } do
        HourglassOutboundEmitterJob.perform_now(
          event_type: 'issue.status_changed', issue_id: @issue.id, actor_id: @user.id, version_id: version.id
        )
      end
    end

    assert_empty captured
  end

  test 'Unauthorized marks the link broken' do
    version = build_version('lane_id' => [@backlog.id, @in_progress.id])
    raise_client = fake_client(raise_with: Hourglass::ApiClient::Unauthorized.new('nope'))

    with_stubbed_client(raise_client) do
      HourglassOutboundEmitterJob.perform_now(
        event_type: 'issue.status_changed', issue_id: @issue.id, actor_id: @user.id, version_id: version.id
      )
    end

    assert_predicate @thread_link.reload, :broken?
  end

  test 'NotFound is swallowed and link stays active' do
    version = build_version('lane_id' => [@backlog.id, @in_progress.id])
    raise_client = fake_client(raise_with: Hourglass::ApiClient::NotFound.new('404'))

    with_stubbed_client(raise_client) do
      HourglassOutboundEmitterJob.perform_now(
        event_type: 'issue.status_changed', issue_id: @issue.id, actor_id: @user.id, version_id: version.id
      )
    end

    assert_predicate @thread_link.reload, :active?
  end

  test 'no-ops when issue or actor is missing' do
    assert_nothing_raised do
      HourglassOutboundEmitterJob.perform_now(event_type: 'issue.created', issue_id: 0, actor_id: @user.id)
      HourglassOutboundEmitterJob.perform_now(event_type: 'issue.created', issue_id: @issue.id, actor_id: 0)
    end
  end
end
