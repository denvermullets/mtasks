require 'test_helper'

class DependencyOverlayHelperTest < ActionView::TestCase
  setup do
    @user = User.create!(name: 'Helper User', email: 'issues_helper@example.com', password: 'password')
    @team = Workspace.create!(name: 'Helper Workspace', owner: @user).teams.create!(name: 'Helper', identifier: 'HLP')
    lane = @team.lanes.create!(name: 'Backlog', position: 0)
    @a, @b, @c, @off_board = %w[A B C D].map { |title| @team.issues.create!(title: title, lane: lane, creator: @user) }

    IssueDependency.create!(blocking_issue: @a, blocked_issue: @b)
    IssueDependency.create!(blocking_issue: @b, blocked_issue: @c, kind: 'relates')
    IssueDependency.create!(blocking_issue: @c, blocked_issue: @a, kind: 'duplicates')
    IssueDependency.create!(blocking_issue: @a, blocked_issue: @off_board)
  end

  test 'board_dependency_edges returns every kind of link between board issues' do
    edges = board_dependency_edges(board([@a, @b, @c]))

    expected = [
      { from_id: @a.id, to_id: @b.id, kind: 'blocks' },
      { from_id: @b.id, to_id: @c.id, kind: 'relates' },
      { from_id: @c.id, to_id: @a.id, kind: 'duplicates' }
    ]
    assert_equal(expected.sort_by { |edge| edge[:from_id] }, edges.sort_by { |edge| edge[:from_id] })
  end

  test 'board_dependency_edges skips links whose other end is not on the board' do
    assert_empty board_dependency_edges(board([@a, @c]).reject { |issue| issue == @c })
    assert_equal [{ from_id: @c.id, to_id: @a.id, kind: 'duplicates' }], board_dependency_edges(board([@a, @c]))
  end

  test 'board_dependency_edges counts an issue shown in two columns once' do
    assert_equal 1, board_dependency_edges(board([@a, @b, @a])).size
  end

  test 'board_dependency_edges uses preloaded links without querying' do
    issues = board([@a, @b, @c])

    assert_no_queries { board_dependency_edges(issues) }
  end

  private

  def board(issues)
    Issue.where(id: issues.map(&:id)).includes(:outgoing_links).to_a.then do |loaded|
      issues.map { |issue| loaded.find { |candidate| candidate.id == issue.id } }
    end
  end
end
