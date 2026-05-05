require 'test_helper'

class HourglassLinkReadStateTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'RS', email: 'read_state@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'T', identifier: 'RST')
    @team.team_memberships.create!(user: @user)
    @lane = @team.lanes.create!(name: 'Backlog', position: 0)
    @issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
    @link = @team.hourglass_links.create!(
      link_type: 'issue_thread',
      mtasks_issue: @issue,
      mtasks_issue_identifier: @issue.identifier,
      hourglass_thread_id: 'T_1',
      created_by_user: @user
    )
  end

  test 'creates with user, link, and timestamp' do
    state = HourglassLinkReadState.create!(user: @user, hourglass_link: @link, last_read_at: Time.current)
    assert state.persisted?
  end

  test 'rejects duplicate (user, link) pair' do
    HourglassLinkReadState.create!(user: @user, hourglass_link: @link, last_read_at: Time.current)
    assert_raises(ActiveRecord::RecordNotUnique) do
      HourglassLinkReadState.new(user: @user, hourglass_link: @link, last_read_at: Time.current).save(validate: false)
    end
  end

  test 'is destroyed when link is destroyed' do
    HourglassLinkReadState.create!(user: @user, hourglass_link: @link, last_read_at: Time.current)
    assert_difference 'HourglassLinkReadState.count', -1 do
      @link.destroy!
    end
  end
end
