# The sub-issue tree an issue belongs to: walks up parent links to the top-level issue, then
# down through every sub-issue, one query per level. Nesting is unlimited in the data, so both
# walks are capped; `truncated` says the downward walk stopped with levels left to show.
class IssueHierarchyQuery < Service
  MAX_DEPTH = 10

  # `ancestors` runs root -> direct parent (empty when `issue` is top-level). `children` maps a
  # parent id to its sub-issues in display order; a leaf has no key. `edges` are blocks links
  # between issues in the tree, shaped like DependencyGraphQuery's.
  Result = Data.define(:issue, :root, :ancestors, :children, :edges, :truncated, :issues_by_id) do
    def truncated?
      truncated
    end

    def children_of(issue)
      children.fetch(issue.id, [])
    end

    def single_issue?
      issues_by_id.size == 1
    end
  end

  def initialize(issue:, max_depth: MAX_DEPTH)
    @issue = issue
    @max_depth = max_depth.to_i.clamp(1, MAX_DEPTH)
  end

  def call
    ancestor_ids = walk_up
    root_id = ancestor_ids.first || @issue.id
    child_ids_by_parent, truncated = walk_down(root_id, seen: Set[root_id])

    ids = [root_id, *ancestor_ids, *child_ids_by_parent.values.flatten].uniq
    issues_by_id = preload(ids)
    # The focus issue itself is always present, even if it's archived.
    issues_by_id[@issue.id] ||= @issue

    Result.new(
      issue: issues_by_id.fetch(@issue.id),
      root: issues_by_id.fetch(root_id, @issue),
      ancestors: ancestor_ids.filter_map { |id| issues_by_id[id] },
      children: build_children(child_ids_by_parent, issues_by_id),
      edges: blocks_edges(issues_by_id.keys),
      truncated: truncated,
      issues_by_id: issues_by_id
    )
  end

  private

  # Returns ancestor ids root-first. Stops at an archived or other-team ancestor (the highest
  # visible one becomes the root), and the visited set stops a legacy cycle.
  def walk_up
    ids = []
    visited = Set[@issue.id]
    current = @issue.parent_issue_id
    while current && visited.exclude?(current) && ids.size < @max_depth
      row = scope.where(id: current).pluck(:id, :parent_issue_id).first
      break unless row

      visited << current
      ids.unshift(current)
      current = row.last
    end
    ids
  end

  # Returns [{ parent_id => [child ids] }, truncated?]. Depth counts from the root, so the cap
  # bounds the whole tree rather than just the part under the focus issue.
  def walk_down(root_id, seen:)
    by_parent = Hash.new { |hash, key| hash[key] = [] }
    frontier = [root_id]

    @max_depth.times do
      rows = scope.where(parent_issue_id: frontier).where.not(id: seen.to_a).pluck(:id, :parent_issue_id)
      return [by_parent, false] if rows.empty?

      rows.each { |id, parent_id| by_parent[parent_id] << id }
      frontier = rows.map(&:first)
      seen.merge(frontier)
    end

    [by_parent, scope.exists?(parent_issue_id: frontier)]
  end

  def build_children(child_ids_by_parent, issues_by_id)
    child_ids_by_parent.transform_values do |ids|
      ids.filter_map { |id| issues_by_id[id] }.sort_by { |issue| [issue.lane.position, issue.team_number] }
    end
  end

  def preload(ids)
    scope.where(id: ids).includes(:team, :lane, :labels, :assignee, :project).index_by(&:id)
  end

  def blocks_edges(ids)
    IssueDependency.blocks
                   .where(blocking_issue_id: ids, blocked_issue_id: ids)
                   .pluck(:blocking_issue_id, :blocked_issue_id, :kind)
                   .map { |from_id, to_id, kind| { from_id: from_id, to_id: to_id, kind: kind } }
  end

  def scope
    Issue.where(team_id: @issue.team_id, archived_at: nil)
  end
end
