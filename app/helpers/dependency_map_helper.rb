# Dependency map page: lays a DependencyGraphQuery result out as depth columns and list rows.
module DependencyMapHelper
  RELATED_TAGS = { 'duplicates' => 'Duplicates', 'duplicated_by' => 'Duplicated by' }.freeze

  # Upstream deepest-first, then downstream nearest-first, as [{ side:, depth:, issues: }].
  # The focus card sits between the two halves.
  def dependency_map_columns(graph, side)
    buckets = side == :upstream ? graph.upstream : graph.downstream
    depths = buckets.keys.sort
    depths.reverse! if side == :upstream
    depths.map { |depth| { side: side, depth: depth, issues: buckets[depth] } }
  end

  def dependency_map_empty?(graph)
    graph.upstream.empty? && graph.downstream.empty? && graph.related.empty?
  end

  # Links between the focus and its related issues are drawn as a static stub under the focus
  # card, so the connector layer only gets the rest.
  def dependency_map_edges(graph)
    focus_id = graph.issue.id
    graph.edges.reject do |edge|
      edge[:kind] != 'blocks' && (edge[:from_id] == focus_id || edge[:to_id] == focus_id)
    end
  end

  def dependency_map_related_rows(graph)
    graph.related.map do |entry|
      { issue: entry[:issue], kind: entry[:kind], tag: RELATED_TAGS[entry[:direction]] }
    end
  end

  def dependency_node_closed?(issue)
    issue.completed_at.present? || issue.canceled_at.present?
  end
end
