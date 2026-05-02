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

  test 'project_channel uniqueness blocks two rows for same project' do
    @team.hourglass_links.create!(
      link_type: 'project_channel',
      mtasks_project: @project,
      hourglass_channel_id: 'chan_a'
    )
    assert_raises(ActiveRecord::RecordInvalid) do
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

  test 'status defaults to active' do
    link = @team.hourglass_links.create!(
      link_type: 'project_channel',
      mtasks_project: @project,
      hourglass_channel_id: 'chan_x'
    )
    assert link.active?
  end

  test 'status enum allows broken' do
    link = @team.hourglass_links.create!(
      link_type: 'project_channel',
      mtasks_project: @project,
      hourglass_channel_id: 'chan_y'
    )
    link.update!(status: 'broken')
    assert link.broken?
  end

  test 'for_project scope returns only that project channel link' do
    other_project = @team.projects.create!(name: 'P2')
    @team.hourglass_links.create!(
      link_type: 'project_channel', mtasks_project: @project, hourglass_channel_id: 'a'
    )
    @team.hourglass_links.create!(
      link_type: 'project_channel', mtasks_project: other_project, hourglass_channel_id: 'b'
    )

    scoped = HourglassLink.for_project(@project)
    assert_equal 1, scoped.count
    assert_equal @project.id, scoped.first.mtasks_project_id
  end
end
