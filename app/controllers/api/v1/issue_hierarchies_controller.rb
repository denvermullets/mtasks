module Api
  module V1
    # GET /api/v1/teams/:team_id/issues/:issue_id/hierarchy
    #
    # The sub-issue tree the issue belongs to, as one nested document rooted at the top-level
    # issue, so the MCP server and the desktop app can draw it without walking parents
    # themselves. Same data as the web Hierarchy view (IssueHierarchyQuery). `max_depth`
    # (1-10, default 10) bounds the downward walk; `truncated` says levels were left out.
    class IssueHierarchiesController < BaseController
      before_action :set_current_team

      def show
        issue = current_team.issues.find_by(id: params[:issue_id])
        return render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found unless issue

        max_depth = params.fetch(:max_depth, IssueHierarchyQuery::MAX_DEPTH)
        result = IssueHierarchyQuery.call(issue: issue, max_depth: max_depth)
        @tracked_result_count = result.issues_by_id.size

        render json: serialize(result)
      end

      private

      def serialize(result)
        {
          issue_id: result.issue.id,
          root_id: result.root.id,
          ancestor_ids: result.ancestors.map(&:id),
          truncated: result.truncated?,
          tree: serialize_node(result.root, result),
          # Blocks links between issues in the tree (blocking issue -> blocked issue).
          blocks: result.edges.map { |edge| { blocking_issue_id: edge[:from_id], blocked_issue_id: edge[:to_id] } }
        }
      end

      def serialize_node(issue, result)
        children = result.children_of(issue)
        {
          id: issue.id,
          identifier: issue.identifier,
          title: issue.title,
          priority: issue.priority,
          lane: { id: issue.lane.id, name: issue.lane.name, category: issue.lane.category },
          assignee: issue.assignee && { id: issue.assignee.id, name: issue.assignee.name },
          closed: issue.closed?,
          sub_issue_count: children.size,
          sub_issues: children.map { |child| serialize_node(child, result) }
        }
      end
    end
  end
end
