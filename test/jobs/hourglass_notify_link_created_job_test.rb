require 'test_helper'

class HourglassNotifyLinkCreatedJobTest < ActiveJob::TestCase
  def with_stubbed_client(client)
    Hourglass::ApiClient.singleton_class.alias_method(:_orig_for_integration, :for_integration)
    Hourglass::ApiClient.define_singleton_method(:for_integration) { |_| client }
    yield
  ensure
    Hourglass::ApiClient.singleton_class.alias_method(:for_integration, :_orig_for_integration)
    Hourglass::ApiClient.singleton_class.send(:remove_method, :_orig_for_integration)
  end

  setup do
    @user = User.create!(name: 'NL', email: 'notify_link@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'NLJ')
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

  test 'calls notify_link_created on api client' do
    captured = {}
    fake = Object.new
    fake.define_singleton_method(:notify_link_created) do |**kwargs|
      captured.merge!(kwargs)
      {}
    end

    with_stubbed_client(fake) do
      HourglassNotifyLinkCreatedJob.perform_now(@link.id)
    end

    assert_equal 'C1', captured[:channel_id]
    assert_equal @project.id, captured[:project].id
  end

  test 'marks link broken on Unauthorized' do
    fake = Object.new
    fake.define_singleton_method(:notify_link_created) do |**|
      raise Hourglass::ApiClient::Unauthorized, 'no'
    end

    with_stubbed_client(fake) do
      HourglassNotifyLinkCreatedJob.perform_now(@link.id)
    end

    assert_predicate @link.reload, :broken?
  end

  test 'no-ops when link missing' do
    assert_nothing_raised do
      HourglassNotifyLinkCreatedJob.perform_now(0)
    end
  end
end
