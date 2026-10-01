# Every issue in a project, laid out left to right by the blocks chain: column 0 holds issues
# nothing in the graph blocks (including ones with no links at all), and each later column holds
# issues blocked by something in an earlier one. Issues outside the project show up when a project
# issue links to them directly. Fixed query count regardless of project size.
class ProjectDependencyGraphQuery < Service
  # `columns` is [[Issue]] in display order. `edges` are { from_id:, to_id:, kind: }.
  Result = Data.define(:project, :columns, :edges, :active_only) do
    def empty?
      columns.empty?
    end
  end

  # active_only drops completed/canceled issues (by timestamp or lane category), along with any
  # links to them.
  def initialize(project:, active_only: false)
    @project = project
    @active_only = active_only
  end

  def call
    project_issues = preload(scope.where(project_id: @project.id))
    issues_by_id, edges = load_graph(project_issues, links_touching(project_issues.keys))
    index_edges(edges)

    Result.new(project: @project, columns: layout(issues_by_id), edges: edges, active_only: @active_only)
  end

  private

  def scope
    base = Issue.where(team_id: @project.team_id, archived_at: nil)
    @active_only ? base.active : base
  end

  def preload(relation)
    relation.includes(:team, :lane, :labels, :assignee, :project).index_by(&:id)
  end

  def links_touching(ids)
    IssueDependency.where(blocking_issue_id: ids)
                   .or(IssueDependency.where(blocked_issue_id: ids))
                   .distinct
                   .pluck(:blocking_issue_id, :blocked_issue_id, :kind)
                   .map { |from_id, to_id, kind| { from_id: from_id, to_id: to_id, kind: kind } }
  end

  # The scope drops other-team, archived (and with active_only, closed) issues, so links to them
  # go too. Outside issues only come in through a surviving link.
  def load_graph(project_issues, links)
    outside_ids = links.flat_map { |link| [link[:from_id], link[:to_id]] }.uniq - project_issues.keys
    loaded = project_issues.merge(preload(scope.where(id: outside_ids)))
    edges = links.select { |link| loaded.key?(link[:from_id]) && loaded.key?(link[:to_id]) }
    [loaded, edges]
  end

  # Adjacency lists: @blockers / @blocked over blocks edges, @related over the rest (both ways).
  def index_edges(edges)
    @blockers = {}
    @blocked = {}
    @related = {}

    edges.each do |edge|
      from, to = edge.values_at(:from_id, :to_id)
      if edge[:kind] == 'blocks'
        (@blockers[to] ||= []) << from
        (@blocked[from] ||= []) << to
      else
        (@related[from] ||= []) << to
        (@related[to] ||= []) << from
      end
    end
  end

  def layout(issues_by_id)
    ranks = ranks_for(issues_by_id.keys)
    columns = issues_by_id.values.group_by { |issue| ranks[issue.id] }.sort.map(&:last)
    order_columns(columns)
  end

  def linked?(id)
    in_chain?(id) || @related.key?(id)
  end

  def in_chain?(id)
    @blockers.key?(id) || @blocked.key?(id)
  end

  # Longest path from a source over blocks edges. Issues with only relates/duplicates links sit
  # beside the partner they link to.
  def ranks_for(ids)
    ranks = chain_ranks(ids)
    ids.reject { |id| in_chain?(id) }.each do |id|
      partner_ranks = @related.fetch(id, []).filter_map { |partner| ranks[partner] if in_chain?(partner) }
      ranks[id] = partner_ranks.min if partner_ranks.any?
    end
    ranks
  end

  # Kahn's algorithm. Issues stuck in (or behind) a legacy cycle never drain, so they land one
  # past their furthest placed blocker.
  def chain_ranks(ids)
    pending = ids.index_with { |id| @blockers.fetch(id, []).size }
    ranks = drain(ids.select { |id| pending[id].zero? }, pending)
    stuck, drained = ids.partition { |id| pending[id].positive? }

    stuck.each do |id|
      ranks[id] = ranks.values_at(*(@blockers[id] & drained)).max.to_i + 1
    end
    ranks
  end

  def drain(queue, pending)
    ranks = queue.index_with(0)
    until queue.empty?
      id = queue.shift
      @blocked.fetch(id, []).each do |next_id|
        ranks[next_id] = [ranks[next_id] || 0, ranks[id] + 1].max
        pending[next_id] -= 1
        queue << next_id if pending[next_id].zero?
      end
    end
    ranks
  end

  # First column puts linked issues above unlinked ones, then sorts by status and number; each
  # later column by the average row of its linked issues in earlier columns, which keeps most
  # lines from crossing.
  def order_columns(columns)
    rows = {}
    columns.each_with_index.map do |column, index|
      ordered = if index.zero?
                  column.sort_by { |issue| first_column_key(issue) }
                else
                  column.sort_by { |issue| [barycenter(issue.id, rows) || Float::INFINITY, *sort_key(issue)] }
                end
      ordered.each_with_index { |issue, row| rows[issue.id] = row }
      ordered
    end
  end

  def first_column_key(issue)
    [linked?(issue.id) ? 0 : 1, *sort_key(issue)]
  end

  def barycenter(id, rows)
    neighbors = [@blockers, @blocked, @related].flat_map { |adjacency| adjacency.fetch(id, []) }
    placed = neighbors.filter_map { |other| rows[other] }
    placed.sum.fdiv(placed.size) if placed.any?
  end

  def sort_key(issue)
    [issue.lane.position, issue.team_number]
  end
end
