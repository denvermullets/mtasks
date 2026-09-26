# Board "Dependencies" overlay: which lines to draw and where a linked card leads. Split out of
# IssuesHelper to keep that module under Metrics/ModuleLength.
module DependencyOverlayHelper
  # Every blocks/relates/duplicates link between two issues rendered on the board, as
  # [{ from_id:, to_id:, kind: }] for the dependency overlay. Links to anything the board isn't
  # showing (filtered out, archived, hidden sub-issue) are dropped so no line dangles. Reads the
  # preloaded `outgoing_links`, so it adds no queries.
  def board_dependency_edges(issues)
    board_ids = issues.to_set(&:id)
    issues.uniq(&:id).flat_map do |issue|
      issue.outgoing_links.filter_map do |link|
        next unless board_ids.include?(link.blocked_issue_id)

        { from_id: link.blocking_issue_id, to_id: link.blocked_issue_id, kind: link.kind }
      end
    end
  end

  def board_issues(grouped_issues)
    grouped_issues.values.flat_map { |group_data| group_data[:issues] }
  end

  def dependency_map_path_for(issue)
    team_issue_dependency_map_path(issue.team_id, issue)
  end
end
