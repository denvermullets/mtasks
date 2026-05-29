require 'test_helper'

class DiscussionStreamServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'DS', email: 'discussion_stream@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'DST')
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
  end

  test 'returns empty when no channel link' do
    project_no_link = @team.projects.create!(name: 'NL')
    assert_equal [], DiscussionStreamService.call(project: project_no_link)
  end

  test 'interleaves chat + native chronologically' do
    HourglassMessageCache.create!(
      hourglass_message_id: 'm1', hourglass_channel_id: 'C1',
      body: 'first chat', posted_at: 3.minutes.ago, source: 'webhook'
    )
    @project.comments.create!(user: @user, body: 'middle native', created_at: 2.minutes.ago)
    HourglassMessageCache.create!(
      hourglass_message_id: 'm2', hourglass_channel_id: 'C1',
      body: 'last chat', posted_at: 1.minute.ago, source: 'webhook'
    )

    items = DiscussionStreamService.call(project: @project)
    assert_equal %i[hourglass native hourglass], items.map(&:kind)
    assert_equal(['first chat', 'middle native', 'last chat'], items.map { |i| i.record.body })
  end

  test 'excludes deleted hourglass messages' do
    HourglassMessageCache.create!(
      hourglass_message_id: 'm1', hourglass_channel_id: 'C1',
      body: 'gone', posted_at: 1.minute.ago, deleted_at: 30.seconds.ago, source: 'webhook'
    )
    HourglassMessageCache.create!(
      hourglass_message_id: 'm2', hourglass_channel_id: 'C1',
      body: 'alive', posted_at: 30.seconds.ago, source: 'webhook'
    )

    items = DiscussionStreamService.call(project: @project)
    assert_equal(['alive'], items.map { |i| i.record.body })
  end

  test 'scopes hourglass to the linked channel only' do
    HourglassMessageCache.create!(
      hourglass_message_id: 'm1', hourglass_channel_id: 'OTHER',
      body: 'wrong channel', posted_at: 1.minute.ago, source: 'webhook'
    )
    HourglassMessageCache.create!(
      hourglass_message_id: 'm2', hourglass_channel_id: 'C1',
      body: 'right channel', posted_at: 30.seconds.ago, source: 'webhook'
    )

    items = DiscussionStreamService.call(project: @project)
    assert_equal(['right channel'], items.map { |i| i.record.body })
  end

  test 'with issue + issue_thread_link merges thread messages and issue comments' do
    lane = @team.lanes.create!(name: 'L', position: 0)
    issue = @team.issues.create!(title: 'I', lane: lane, creator: @user)
    thread_link = @team.hourglass_links.create!(
      link_type: 'issue_thread',
      mtasks_issue: issue,
      mtasks_issue_identifier: issue.identifier,
      hourglass_thread_id: 'T_42',
      hourglass_integration: @integration,
      created_by_user: @user
    )

    HourglassMessageCache.create!(
      hourglass_message_id: 'tm1', hourglass_channel_id: 'C1', hourglass_thread_id: 'T_42',
      body: 'in-thread chat', posted_at: 2.minutes.ago, source: 'webhook'
    )
    HourglassMessageCache.create!(
      hourglass_message_id: 'cm1', hourglass_channel_id: 'C1',
      body: 'channel-only chat', posted_at: 1.minute.ago, source: 'webhook'
    )
    issue.comments.create!(user: @user, body: 'native on issue', created_at: 90.seconds.ago)

    items = DiscussionStreamService.call(issue: issue, issue_thread_link: thread_link)
    bodies = items.map { |i| i.record.body }

    assert_equal %w[hourglass native].sort, items.map(&:kind).map(&:to_s).uniq.sort
    assert_includes bodies, 'in-thread chat'
    assert_includes bodies, 'native on issue'
    assert_not_includes bodies, 'channel-only chat'
  end
end
