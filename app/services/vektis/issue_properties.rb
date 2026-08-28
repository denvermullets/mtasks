# The §4.1 / §5.2 rules for describing an issue in `properties`, extracted from VEK-584's
# controller concerns so VEK-585 can reuse them from a background job.
#
# GithubPrSyncService moves issues between lanes with no user and no request — a merged PR can
# complete an issue — and taxonomy §4.5 requires that to emit the same issue-workflow event the
# web path emits. Two copies of the precedence table would drift the moment a lane rule changes,
# and the drift would be invisible: both copies would keep emitting, just disagreeing.
module Vektis
  module IssueProperties
    # Attributes whose change means "the user edited this issue" (§4.1). Deliberately excludes
    # lane_id / completed_at / canceled_at (issue-workflow owns those), parent_issue_id (sub-issue)
    # and labels (issue-label) — that exclusion is what keeps a lane-only PATCH exactly one event.
    #
    # Lives here rather than in a controller concern because the web form and the v1 API both save
    # issues and must agree on what an edit is. Two copies would drift the moment a field is added,
    # and the drift would be invisible: both would keep emitting, just disagreeing about when.
    EDIT_FIELDS = %w[title description priority estimate due_date assignee_id project_id].freeze

    module_function

    # §4.1, most specific wins. Done -> Cancelled clears completed_at *and* sets canceled_at;
    # `cancel` is the truthful label for that gesture, so it is checked before `reopen`.
    def workflow_action(issue)
      return 'complete' if timestamp_set?(issue, :completed_at)
      return 'cancel' if timestamp_set?(issue, :canceled_at)
      return 'reopen' if timestamp_cleared?(issue, :completed_at) || timestamp_cleared?(issue, :canceled_at)

      'move'
    end

    # Lane *names* are user-authored free text and may never ship (§6); position is the registered
    # stand-in and is comparable across teams.
    #
    # `lanes:` takes a collection the caller has already loaded — the web path passes the relation
    # the form and the turbo_stream template already render, so the whole request costs no extra
    # query. The job path has no such collection and pays one pluck.
    def lane_move(issue, lanes: nil)
      from_id, to_id = issue.saved_change_to_lane_id
      positions = lane_positions([from_id, to_id], lanes)
      from = positions[from_id]
      to = positions[to_id]
      return { to_position: to } if from.nil? || to.nil?

      { from_position: from, to_position: to, direction: to > from ? 'forward' : 'backward' }
    end

    # The §5.2 shape keys, read from attributes already in memory. No queries, no free text.
    def shape(issue)
      {
        priority: issue.priority,
        has_project: issue.project_id.present?,
        has_assignee: issue.assignee_id.present?,
        has_estimate: issue.estimate.present?,
        has_due_date: issue.due_date.present?,
        is_sub_issue: issue.parent_issue_id.present?
      }
    end

    def timestamp_set?(issue, attribute)
      before, after = issue.saved_changes[attribute.to_s]
      before.nil? && after.present?
    end

    def timestamp_cleared?(issue, attribute)
      before, after = issue.saved_changes[attribute.to_s]
      before.present? && after.nil?
    end

    def lane_positions(ids, lanes)
      ids = ids.compact
      return {} if ids.empty?
      return lanes.select { |lane| ids.include?(lane.id) }.to_h { |lane| [lane.id, lane.position] } if lanes

      Lane.where(id: ids).pluck(:id, :position).to_h
    end
  end
end
