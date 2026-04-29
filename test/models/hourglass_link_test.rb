require 'test_helper'

class HourglassLinkTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'HG User', email: 'hg_link@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'HG WS', owner: @user)
    @team = @workspace.teams.create!(name: 'HG Team', identifier: 'HGL')
    @team.team_memberships.create!(user: @user)
    @backlog = @team.lanes.find_by(name: 'Backlog') || @team.lanes.first
    @project = @team.projects.create!(name: 'P1')
    @issue = @team.issues.create!(title: 'I1', lane: @backlog, creator: @user, project: @project)
  end

  test 'project_channel link is valid with project + channel' do
    link = @team.hourglass_links.new(
      link_type: 'project_channel',
      mtasks_project: @project,
      hourglass_channel_id: 'chan_1'
    )
    assert link.valid?, link.errors.full_messages.inspect
  end

  test 'project_channel link rejects issue/thread fields' do
    link = @team.hourglass_links.new(
      link_type: 'project_channel',
      mtasks_project: @project,
      hourglass_channel_id: 'chan_1',
      mtasks_issue: @issue
    )
    assert_not link.valid?
  end

  test 'issue_thread link is valid with issue + thread' do
    link = @team.hourglass_links.new(
      link_type: 'issue_thread',
      mtasks_issue: @issue,
      hourglass_thread_id: 'thr_1'
    )
    assert link.valid?, link.errors.full_messages.inspect
  end

  test 'rejects unknown link_type' do
    link = @team.hourglass_links.new(link_type: 'wat', mtasks_project: @project, hourglass_channel_id: 'c')
    assert_not link.valid?
  end

  test 'partial unique index blocks two project_channel rows for same project' do
    @team.hourglass_links.create!(
      link_type: 'project_channel',
      mtasks_project: @project,
      hourglass_channel_id: 'chan_a'
    )
    assert_raises(ActiveRecord::RecordNotUnique) do
      @team.hourglass_links.create!(
        link_type: 'project_channel',
        mtasks_project: @project,
        hourglass_channel_id: 'chan_b'
      )
    end
  end

  test 'partial unique index blocks two issue_thread rows for same issue' do
    @team.hourglass_links.create!(
      link_type: 'issue_thread',
      mtasks_issue: @issue,
      hourglass_thread_id: 'thr_a'
    )
    assert_raises(ActiveRecord::RecordNotUnique) do
      @team.hourglass_links.create!(
        link_type: 'issue_thread',
        mtasks_issue: @issue,
        hourglass_thread_id: 'thr_b'
      )
    end
  end
end
