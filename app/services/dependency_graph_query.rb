# Walks the blocks chain around one issue: everything that transitively blocks it (upstream),
# everything it transitively blocks (downstream), plus its direct relates/duplicates links.
# Batched BFS, one query per depth level and direction, so the dependency map stays a thin view.
class DependencyGraphQuery < Service
  DEFAULT_MAX_DEPTH = 3

  # `upstream` / `downstream` are { depth => [Issue] }, each node at the shallowest depth it was
  # reached. `related` entries are { issue:, kind:, direction: } with direction relative to
  # `issue`. `edges` are { from_id:, to_id:, kind: } for every link between nodes in the result.
  Result = Data.define(:issue, :upstream, :downstream, :related, :edges, :truncated, :issues_by_id) do
    def truncated?
      truncated
    end
  end

  # direction => [column matched against the frontier, column holding the neighbor, neighbor association]
  DIRECTIONS = {
    upstream: %i[blocked_issue_id blocking_issue_id blocking_issue],
    downstream: %i[blocking_issue_id blocked_issue_id blocked_issue]
  }.freeze

  def initialize(issue:, max_depth: DEFAULT_MAX_DEPTH)
    @issue = issue
    @max_depth = max_depth.to_i
  end

  def call
    # Shared across directions (and seeded with the focus) so legacy cycles still terminate.
    @visited = Set[@issue.id]
    upstream_ids, upstream_frontier = traverse(:upstream)
    downstream_ids, downstream_frontier = traverse(:downstream)
    truncated = cut_off?(upstream: upstream_frontier, downstream: downstream_frontier)

    related_links = related_links_for_issue
    issues_by_id = preload(@visited.to_a | related_links.map { |link| other_id(link) })

    Result.new(
      issue: issues_by_id.fetch(@issue.id, @issue),
      upstream: bucket(upstream_ids, issues_by_id),
      downstream: bucket(downstream_ids, issues_by_id),
      related: related_entries(related_links, issues_by_id),
      edges: edges_between(issues_by_id.keys),
      truncated: truncated,
      issues_by_id: issues_by_id
    )
  end

  private

  # Returns [{ depth => [ids] }, the frontier at max_depth]. The frontier is empty when the
  # walk ran dry first, since then there's nothing past the cutoff to probe for.
  def traverse(direction)
    ids_by_depth = {}
    frontier = [@issue.id]

    (1..@max_depth).each do |depth|
      frontier = neighbor_ids(direction, frontier).reject { |id| @visited.include?(id) }
      break if frontier.empty?

      @visited.merge(frontier)
      ids_by_depth[depth] = frontier
    end

    [ids_by_depth, ids_by_depth.size == @max_depth ? frontier : []]
  end

  # One query for the whole frontier. Joining the neighbor keeps other-team and archived issues
  # out of the walk entirely, even if a bad row links to one.
  def neighbor_ids(direction, frontier)
    match_column, neighbor_column, association = DIRECTIONS.fetch(direction)

    IssueDependency.blocks
                   .joins(association)
                   .where(match_column => frontier, issues: scope_conditions)
                   .distinct
                   .pluck(neighbor_column)
  end

  # Runs after both walks, so a node the other direction picked up doesn't count as cut off.
  def cut_off?(frontiers)
    frontiers.any? do |direction, frontier|
      frontier.any? && neighbor_ids(direction, frontier).any? { |id| !@visited.include?(id) }
    end
  end

  def related_links_for_issue
    IssueDependency.where(kind: %w[relates duplicates])
                   .where(blocking_issue_id: @issue.id)
                   .or(IssueDependency.where(kind: %w[relates duplicates], blocked_issue_id: @issue.id))
                   .to_a
  end

  def other_id(link)
    link.blocking_issue_id == @issue.id ? link.blocked_issue_id : link.blocking_issue_id
  end

  # Anything the scope drops (another team, archived) is missing here, and callers skip it.
  def preload(ids)
    Issue.where(id: ids, **scope_conditions)
         .includes(:team, :lane, :labels, :assignee, :project)
         .index_by(&:id)
  end

  def scope_conditions
    { team_id: @issue.team_id, archived_at: nil }
  end

  def bucket(ids_by_depth, issues_by_id)
    ids_by_depth.transform_values { |ids| sort(ids.filter_map { |id| issues_by_id[id] }) }
  end

  def sort_key(issue)
    [issue.lane.position, issue.team_number]
  end

  def sort(issues)
    issues.sort_by { |issue| sort_key(issue) }
  end

  def related_entries(links, issues_by_id)
    entries = links.filter_map do |link|
      other = issues_by_id[other_id(link)]
      next unless other

      { issue: other, kind: link.kind, direction: IssueDependencies::Link.direction_for(link, @issue) }
    end
    entries.sort_by { |entry| sort_key(entry[:issue]) }
  end

  # One query for every link among the result's nodes, so diamonds and cross-links draw even
  # when BFS reached a node by another path.
  def edges_between(ids)
    IssueDependency.where(blocking_issue_id: ids, blocked_issue_id: ids)
                   .pluck(:blocking_issue_id, :blocked_issue_id, :kind)
                   .map { |from_id, to_id, kind| { from_id: from_id, to_id: to_id, kind: kind } }
  end
end
