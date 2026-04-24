require 'test_helper'

class MentionNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @actor = User.create!(name: 'Alice', email: 'mns_alice@example.com', password: 'password')
    @bob = User.create!(name: 'Bob', email: 'mns_bob@example.com', password: 'password')
    @carol = User.create!(name: 'Carol', email: 'mns_carol@example.com', password: 'password')
    workspace = Workspace.create!(name: 'MNS Workspace', owner: @actor)
    @team = Team.create!(name: 'Team', identifier: 'MNS', workspace: workspace)
    [@actor, @bob, @carol].each { |u| TeamMembership.create!(user: u, team: @team) }
    lane = Lane.create!(name: 'Backlog', team: @team, position: 0)
    @issue = Issue.create!(title: 'T', team: @team, lane: lane, creator: @actor, team_number: 1)
  end

  test 'creates notifications for mentioned users' do
    assert_difference -> { Notification.count }, 2 do
      MentionNotificationService.call(issue: @issue, actor: @actor, text: 'ping @Bob and @Carol')
    end
    assert_equal 'mentioned', Notification.last.action
    assert_equal [@bob, @carol].sort, Notification.last(2).map(&:user).sort
  end

  test 'skips self-mentions' do
    assert_no_difference -> { Notification.count } do
      MentionNotificationService.call(issue: @issue, actor: @actor, text: 'hi @Alice')
    end
  end

  test 'only notifies newly-added mentions on update' do
    assert_difference -> { Notification.count }, 1 do
      MentionNotificationService.call(
        issue: @issue, actor: @actor,
        text: 'ping @Bob and @Carol',
        previous_text: 'ping @Bob'
      )
    end
    assert_equal @carol, Notification.last.user
  end

  test 'links notification to comment when provided' do
    comment = Comment.create!(body: 'hey @Bob', issue: @issue, user: @actor)
    MentionNotificationService.call(
      issue: @issue, actor: @actor, text: comment.body, comment: comment
    )
    note = Notification.last
    assert_equal comment, note.comment
    assert_match(/comment on/, note.message)
  end
end
