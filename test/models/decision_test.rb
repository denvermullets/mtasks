require 'test_helper'

class DecisionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'D User', email: 'd_test@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'D WS', owner: @user)
    @team = @workspace.teams.create!(name: 'D Team', identifier: 'DEC')
    @team.team_memberships.create!(user: @user)
    @backlog = @team.lanes.find_by(name: 'Backlog') || @team.lanes.first
    @project = @team.projects.create!(name: 'P')
    @issue = @team.issues.create!(title: 'I', lane: @backlog, creator: @user, project: @project)
  end

  test 'creates a decision with required fields' do
    decision = @team.decisions.create!(
      project: @project,
      issue: @issue,
      hourglass_message_id: 'msg_1',
      pinned_by_user: @user,
      pinned_at: Time.current,
      body_snapshot: 'Decision text'
    )
    assert decision.persisted?
    assert_nil decision.unpinned_at
  end

  test 'requires body_snapshot' do
    decision = @team.decisions.new(
      hourglass_message_id: 'msg_2',
      pinned_at: Time.current
    )
    assert_not decision.valid?
    assert_includes decision.errors[:body_snapshot], "can't be blank"
  end

  test 'hourglass_message_id is unique' do
    @team.decisions.create!(
      hourglass_message_id: 'msg_dup',
      pinned_at: Time.current,
      body_snapshot: 'A'
    )
    dup = @team.decisions.build(
      hourglass_message_id: 'msg_dup',
      pinned_at: Time.current,
      body_snapshot: 'B'
    )
    assert_not dup.valid?
  end

  test 'active scope excludes unpinned' do
    on  = @team.decisions.create!(hourglass_message_id: 'm_on',  pinned_at: Time.current, body_snapshot: 'x')
    off = @team.decisions.create!(hourglass_message_id: 'm_off', pinned_at: Time.current, body_snapshot: 'y',
                                  unpinned_at: Time.current)

    ids = @team.decisions.active.pluck(:id)
    assert_includes ids, on.id
    assert_not_includes ids, off.id
  end
end
