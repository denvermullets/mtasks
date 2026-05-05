require 'test_helper'

class HourglassNotifyLinkCreatedJobTest < ActiveJob::TestCase
  def with_stubbed_dispatcher(handler)
    original = Hourglass::WebhookDispatcher.method(:call)
    Hourglass::WebhookDispatcher.define_singleton_method(:call) do |**kwargs|
      handler.call(**kwargs)
    end
    yield
  ensure
    Hourglass::WebhookDispatcher.singleton_class.send(:remove_method, :call)
    Hourglass::WebhookDispatcher.define_singleton_method(:call, &original)
  end

  setup do
    @user = User.create!(name: 'NL', email: 'notify_link@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'NLJ')
    @team.team_memberships.create!(user: @user)
    @project = @team.projects.create!(name: 'Proj')
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
      webhook_secret: 'wh', connected_by_user: @user, hourglass_integration_id: 7
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

  test 'dispatches link.created with project_channel data' do
    captured = {}
    handler = ->(**kwargs) { captured.merge!(kwargs) }

    with_stubbed_dispatcher(handler) do
      HourglassNotifyLinkCreatedJob.perform_now(@link.id)
    end

    assert_equal 'link.created', captured[:event_type]
    assert_equal 'project_channel', captured[:data][:link_type]
    assert_equal 'C1', captured[:data][:hourglass_channel_id]
    assert_equal @project.id, captured[:data][:mtasks_project_id]
  end

  test 'marks link broken on Unauthorized' do
    handler = ->(**) { raise Hourglass::ApiClient::Unauthorized, 'no' }

    with_stubbed_dispatcher(handler) do
      HourglassNotifyLinkCreatedJob.perform_now(@link.id)
    end

    assert_predicate @link.reload, :broken?
  end

  test 'leaves link active on NotFound' do
    handler = ->(**) { raise Hourglass::ApiClient::NotFound, '404' }

    with_stubbed_dispatcher(handler) do
      HourglassNotifyLinkCreatedJob.perform_now(@link.id)
    end

    assert_predicate @link.reload, :active?
  end

  test 'no-ops when link missing' do
    assert_nothing_raised { HourglassNotifyLinkCreatedJob.perform_now(0) }
  end

  test 'no-ops when link is not project_channel' do
    issue = @team.issues.create!(title: 'I', creator: @user, lane: @team.lanes.create!(name: 'L', position: 0))
    thread_link = @team.hourglass_links.create!(
      link_type: 'issue_thread', mtasks_issue: issue, mtasks_issue_identifier: issue.identifier,
      hourglass_thread_id: 'T1', hourglass_integration: @integration, created_by_user: @user
    )
    called = false
    handler = ->(**) { called = true }

    with_stubbed_dispatcher(handler) do
      HourglassNotifyLinkCreatedJob.perform_now(thread_link.id)
    end

    assert_not called
  end
end
