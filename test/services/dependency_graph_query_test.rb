require 'test_helper'

class DependencyGraphQueryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Graph User', email: 'dependency_graph@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Graph Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Graph Team', identifier: 'DGQ')
    @other_team = @workspace.teams.create!(name: 'Other Graph Team', identifier: 'DGX')
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @todo = @team.lanes.create!(name: 'Todo', position: 1)
    @other_lane = @other_team.lanes.create!(name: 'Backlog', position: 0)
  end

  test 'a chain focused in the middle splits into upstream and downstream by depth' do
    a, b, c, d = chain(4)

    result = DependencyGraphQuery.call(issue: b)

    assert_equal({ 1 => [a] }, result.upstream)
    assert_equal({ 1 => [c], 2 => [d] }, result.downstream)
    assert_not result.truncated?
    assert_equal [a, b, c, d].map(&:id).sort, result.issues_by_id.keys.sort
  end

  test 'a diamond lists the shared node once and keeps both edges into it' do
    a, b, c, d = Array.new(4) { |i| create_issue("Diamond #{i}") }
    block(a, b)
    block(a, c)
    block(b, d)
    block(c, d)

    result = DependencyGraphQuery.call(issue: a)

    assert_equal [b, c], result.downstream[1]
    assert_equal [d], result.downstream[2]
    assert_includes result.edges, { from_id: b.id, to_id: d.id, kind: 'blocks' }
    assert_includes result.edges, { from_id: c.id, to_id: d.id, kind: 'blocks' }
    assert_equal 4, result.edges.size
  end

  test 'a cycle in legacy data terminates and returns each node once' do
    a, b, c = Array.new(3) { |i| create_issue("Cycle #{i}") }
    insert_links([a, b], [b, c], [c, a])

    result = DependencyGraphQuery.call(issue: a, max_depth: 10)

    assert_equal({ 1 => [c], 2 => [b] }, result.upstream)
    assert_empty result.downstream
    assert_equal [a, b, c].map(&:id).sort, result.issues_by_id.keys.sort
    assert_equal 3, result.edges.size
    assert_not result.truncated?
  end

  test 'max_depth 1 on a long chain returns only direct neighbors and is truncated' do
    issues = chain(7)

    result = DependencyGraphQuery.call(issue: issues[3], max_depth: 1)

    assert_equal({ 1 => [issues[2]] }, result.upstream)
    assert_equal({ 1 => [issues[4]] }, result.downstream)
    assert result.truncated?
  end

  test 'a chain that ends exactly at max_depth is not truncated' do
    a, b, c = chain(3)

    assert_not DependencyGraphQuery.call(issue: a, max_depth: 2).truncated?
    assert DependencyGraphQuery.call(issue: a, max_depth: 1).truncated?
    assert_equal({ 1 => [b], 2 => [c] }, DependencyGraphQuery.call(issue: a, max_depth: 2).downstream)
  end

  test 'issues from another team never appear, even through a bad row' do
    focus = create_issue('Focus')
    outsider = @other_team.issues.create!(title: 'Outsider', lane: @other_lane, creator: @user)
    downstream_outsider = @other_team.issues.create!(title: 'Downstream outsider', lane: @other_lane, creator: @user)
    related_outsider = @other_team.issues.create!(title: 'Related outsider', lane: @other_lane, creator: @user)
    beyond = @other_team.issues.create!(title: 'Beyond', lane: @other_lane, creator: @user)
    insert_links([outsider, focus], [focus, downstream_outsider], [beyond, outsider], [downstream_outsider, beyond])
    insert_links([focus, related_outsider], kind: 'relates')

    result = DependencyGraphQuery.call(issue: focus)

    assert_empty result.upstream
    assert_empty result.downstream
    assert_empty result.related
    assert_empty result.edges
    assert_equal [focus.id], result.issues_by_id.keys
  end

  test 'archived issues are skipped and completed ones are kept' do
    focus = create_issue('Focus')
    archived = create_issue('Archived', archived_at: Time.current)
    done = create_issue('Done', completed_at: Time.current)
    block(archived, focus)
    block(focus, done)

    result = DependencyGraphQuery.call(issue: focus)

    assert_empty result.upstream
    assert_equal({ 1 => [done] }, result.downstream)
  end

  test 'related lists direct relates and duplicates links in both directions' do
    focus = create_issue('Focus')
    relates_out = create_issue('Relates out')
    relates_in = create_issue('Relates in')
    canonical = create_issue('Canonical')
    duplicate = create_issue('Duplicate')
    far = create_issue('Far')
    link(focus, relates_out, 'relates')
    link(relates_in, focus, 'relates')
    link(focus, canonical, 'duplicates')
    link(duplicate, focus, 'duplicates')
    link(relates_out, far, 'relates')

    result = DependencyGraphQuery.call(issue: focus)

    expected = [
      { issue: relates_out, kind: 'relates', direction: 'relates' },
      { issue: relates_in, kind: 'relates', direction: 'relates' },
      { issue: canonical, kind: 'duplicates', direction: 'duplicates' },
      { issue: duplicate, kind: 'duplicates', direction: 'duplicated_by' }
    ]
    assert_equal expected, result.related
    assert_not result.issues_by_id.key?(far.id)
    assert_includes result.edges, { from_id: focus.id, to_id: relates_out.id, kind: 'relates' }
  end

  test 'depth buckets are ordered by lane position, then team number' do
    focus = create_issue('Focus')
    todo_first = create_issue('Todo first', lane: @todo)
    backlog_second = create_issue('Backlog second')
    backlog_third = create_issue('Backlog third')
    [backlog_third, todo_first, backlog_second].each { |issue| block(focus, issue) }

    result = DependencyGraphQuery.call(issue: focus)

    assert_equal [backlog_second, backlog_third, todo_first], result.downstream[1]
  end

  test 'query count depends on depth, not on how many issues are at each level' do
    narrow_focus = create_issue('Narrow')
    narrow_mid = create_issue('Narrow mid')
    block(narrow_focus, narrow_mid)
    block(narrow_mid, create_issue('Narrow leaf'))
    block(create_issue('Narrow blocker'), narrow_focus)

    wide_focus = create_issue('Wide')
    mids = Array.new(5) { |i| create_issue("Wide mid #{i}") }
    mids.each do |mid|
      block(wide_focus, mid)
      2.times { |i| block(mid, create_issue("Wide leaf #{mid.id}-#{i}")) }
    end
    3.times { |i| block(create_issue("Wide blocker #{i}"), wide_focus) }

    narrow = count_queries { DependencyGraphQuery.call(issue: narrow_focus) }
    wide = count_queries { DependencyGraphQuery.call(issue: wide_focus) }

    assert_equal narrow, wide
  end

  private

  def create_issue(title, lane: @backlog, **attrs)
    @team.issues.create!(title: title, lane: lane, creator: @user, **attrs)
  end

  # Returns n issues where each one blocks the next.
  def chain(count)
    issues = Array.new(count) { |i| create_issue("Chain #{i}") }
    issues.each_cons(2) { |blocker, blocked| block(blocker, blocked) }
    issues
  end

  def block(blocker, blocked)
    link(blocker, blocked, 'blocks')
  end

  def link(source, target, kind)
    IssueDependency.create!(blocking_issue: source, blocked_issue: target, kind: kind)
  end

  # Skips validations, the way pre-validation data could have landed.
  def insert_links(*pairs, kind: 'blocks')
    now = Time.current
    IssueDependency.insert_all!(pairs.map do |source, target|
      { blocking_issue_id: source.id, blocked_issue_id: target.id, kind: kind, created_at: now, updated_at: now }
    end)
  end

  def count_queries(&)
    count = 0
    counter = lambda do |*, payload|
      count += 1 unless payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])
    end
    # Uncached so a lookup the first run warmed (the shared lane) still counts on the second.
    ActiveRecord::Base.uncached { ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &) }
    count
  end
end
