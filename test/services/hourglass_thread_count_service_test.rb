require 'test_helper'

class HourglassThreadCountServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'TC', email: 'thread_count@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'TCS')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)
    @issue_with_thread = @team.issues.create!(title: 'A', lane: @lane, creator: @user)
    @issue_without_thread = @team.issues.create!(title: 'B', lane: @lane, creator: @user)
    @link = @team.hourglass_links.create!(
      link_type: 'issue_thread',
      mtasks_issue: @issue_with_thread,
      mtasks_issue_identifier: @issue_with_thread.identifier,
      hourglass_thread_id: 'T_42',
      created_by_user: @user
    )
  end

  test 'returns empty hash when no issues passed' do
    assert_equal({}, HourglassThreadCountService.call(issues: [], user: @user))
  end

  test 'omits issues without a linked thread' do
    result = HourglassThreadCountService.call(issues: [@issue_without_thread], user: @user)
    assert_nil result[@issue_without_thread.id]
  end

  test 'totals count not-deleted messages and treats no read state as fully unread' do
    HourglassMessageCache.create!(
      hourglass_message_id: 'm1', hourglass_channel_id: 'C1',
      hourglass_thread_id: 'T_42', body: 'a', posted_at: 2.minutes.ago, source: 'webhook'
    )
    HourglassMessageCache.create!(
      hourglass_message_id: 'm2', hourglass_channel_id: 'C1',
      hourglass_thread_id: 'T_42', body: 'b', posted_at: 1.minute.ago, source: 'webhook'
    )
    HourglassMessageCache.create!(
      hourglass_message_id: 'm3', hourglass_channel_id: 'C1',
      hourglass_thread_id: 'T_42', body: 'gone', posted_at: 1.minute.ago,
      deleted_at: 30.seconds.ago, source: 'webhook'
    )

    result = HourglassThreadCountService.call(issues: [@issue_with_thread], user: @user)
    assert_equal 2, result[@issue_with_thread.id][:total]
    assert_equal 2, result[@issue_with_thread.id][:unread]
    assert_equal @link.id, result[@issue_with_thread.id][:link_id]
  end

  test 'unread reflects last_read_at' do
    HourglassMessageCache.create!(
      hourglass_message_id: 'm1', hourglass_channel_id: 'C1',
      hourglass_thread_id: 'T_42', body: 'old', posted_at: 5.minutes.ago, source: 'webhook'
    )
    HourglassMessageCache.create!(
      hourglass_message_id: 'm2', hourglass_channel_id: 'C1',
      hourglass_thread_id: 'T_42', body: 'new', posted_at: 1.minute.ago, source: 'webhook'
    )
    HourglassLinkReadState.create!(user: @user, hourglass_link: @link, last_read_at: 3.minutes.ago)

    result = HourglassThreadCountService.call(issues: [@issue_with_thread], user: @user)
    assert_equal 2, result[@issue_with_thread.id][:total]
    assert_equal 1, result[@issue_with_thread.id][:unread]
  end

  test 'counts the thread root message (where hourglass_message_id == thread_id)' do
    HourglassMessageCache.create!(
      hourglass_message_id: 'T_42', hourglass_channel_id: 'C1',
      hourglass_thread_id: nil, body: 'root', posted_at: 5.minutes.ago, source: 'webhook'
    )

    result = HourglassThreadCountService.call(issues: [@issue_with_thread], user: @user)
    assert_equal 1, result[@issue_with_thread.id][:total]
  end
end
