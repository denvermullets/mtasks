require 'test_helper'

class ProjectDependencyGraphQueryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Project Graph User', email: 'project_dependency_graph@example.com',
                         password: 'password')
    @workspace = Workspace.create!(name: 'Project Graph Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Project Graph Team', identifier: 'PDG')
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @project = @team.projects.create!(name: 'Launch')
    @other_project = @team.projects.create!(name: 'Infra')
  end

  test 'columns follow the longest blocks path' do
    a, b, c, d = %w[A B C D].map { |title| create_issue(title) }
    block(a, b)
    block(b, c)
    block(a, c)
    block(d, c)

    result = ProjectDependencyGraphQuery.call(project: @project)

    assert_equal([[a, d], [b], [c]].map { |column| column.map(&:id).sort },
                 result.columns.map { |column| column.map(&:id).sort })
    assert_equal 4, result.edges.size
  end

  test 'pulls in directly linked issues from other projects and keeps unlinked ones' do
    outside = create_issue('Outside', project: @other_project)
    inside = create_issue('Inside')
    loner = create_issue('Loner')
    create_issue('Unrelated', project: @other_project)
    block(outside, inside)

    result = ProjectDependencyGraphQuery.call(project: @project)

    assert_equal [[outside, loner], [inside]], result.columns
  end

  test 'active_only drops closed issues and their links' do
    done = @team.lanes.create!(name: 'Done', position: 1, category: 'completed')
    preview = @team.lanes.create!(name: 'Preview', position: 2, category: 'completed')
    shipped = create_issue('Shipped', lane: done, completed_at: Time.current)
    # In a completed lane but missing completed_at, e.g. moved before the lane was recategorized.
    staged = create_issue('Staged', lane: preview)
    open_issue = create_issue('Open')
    block(shipped, open_issue)
    block(staged, open_issue)

    all = ProjectDependencyGraphQuery.call(project: @project)
    active = ProjectDependencyGraphQuery.call(project: @project, active_only: true)

    assert_equal [shipped, staged, open_issue].map(&:id).sort, all.columns.flatten.map(&:id).sort
    assert_equal [[open_issue]], active.columns
    assert_empty active.edges
  end

  test 'related-only issues sit beside their partner' do
    a, b, c = %w[A B C].map { |title| create_issue(title) }
    block(a, b)
    IssueDependency.create!(blocking_issue: b, blocked_issue: c, kind: 'relates')

    result = ProjectDependencyGraphQuery.call(project: @project)

    assert_equal [[a], [b, c]], result.columns
  end

  test 'a legacy cycle still places every issue' do
    a, b, c = %w[A B C].map { |title| create_issue(title) }
    block(a, b)
    # Bypass validations the way old data would have.
    IssueDependency.insert_all!([{ blocking_issue_id: b.id, blocked_issue_id: c.id, kind: 'blocks' },
                                 { blocking_issue_id: c.id, blocked_issue_id: b.id, kind: 'blocks' }])

    result = ProjectDependencyGraphQuery.call(project: @project)

    assert_equal [a, b, c].map(&:id).sort, result.columns.flatten.map(&:id).sort
    assert_equal [a], result.columns.first
  end

  test 'archived issues are left out' do
    a = create_issue('A')
    gone = create_issue('Gone', archived_at: Time.current)
    block(a, gone)

    result = ProjectDependencyGraphQuery.call(project: @project)

    assert_equal [[a]], result.columns
    assert_empty result.edges
  end

  private

  def create_issue(title, project: @project, lane: @backlog, **attrs)
    @team.issues.create!(title: title, lane: lane, creator: @user, project: project, **attrs)
  end

  def block(from, to)
    IssueDependency.create!(blocking_issue: from, blocked_issue: to, kind: 'blocks')
  end
end
