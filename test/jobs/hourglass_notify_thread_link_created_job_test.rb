require 'test_helper'

class HourglassNotifyThreadLinkCreatedJobTest < ActiveJob::TestCase
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
    @user = User.create!(name: 'TL', email: 'thread_link@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'TLN')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'L', position: 0)
    @issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: 'srv', hourglass_integration_id: 7,
      base_url: 'https://hg.test', api_token: 'tok', webhook_secret: 'wh',
      connected_by_user: @user
    )
    @link = @team.hourglass_links.create!(
      link_type: 'issue_thread',
      mtasks_issue: @issue,
      mtasks_issue_identifier: @issue.identifier,
      hourglass_thread_id: 'T_42',
      hourglass_integration: @integration,
      created_by_user: @user
    )
  end

  test 'dispatches link.created with issue_thread payload' do
    captured = {}
    handler = ->(**kwargs) { captured.merge!(kwargs) }

    with_stubbed_dispatcher(handler) do
      HourglassNotifyThreadLinkCreatedJob.perform_now(@link.id)
    end

    assert_equal 'link.created', captured[:event_type]
    assert_equal 'issue_thread', captured[:data][:link_type]
    assert_equal @issue.id, captured[:data][:mtasks_issue_id]
    assert_equal 'T_42', captured[:data][:hourglass_thread_id]
  end

  test 'marks link broken on Unauthorized' do
    handler = ->(**) { raise Hourglass::ApiClient::Unauthorized, 'no' }

    with_stubbed_dispatcher(handler) do
      HourglassNotifyThreadLinkCreatedJob.perform_now(@link.id)
    end

    assert_predicate @link.reload, :broken?
  end

  test 'no-ops on a non-issue_thread link' do
    project = @team.projects.create!(name: 'P')
    project_link = @team.hourglass_links.create!(
      link_type: 'project_channel', mtasks_project: project,
      hourglass_channel_id: 'C9', hourglass_integration: @integration, created_by_user: @user
    )
    called = false
    handler = ->(**) { called = true }

    with_stubbed_dispatcher(handler) do
      HourglassNotifyThreadLinkCreatedJob.perform_now(project_link.id)
    end

    assert_not called
  end
end
