# The issue call sites for Api::V1::IssuesController — the API's counterpart to
# VektisIssueTracking, kept out of the controller for the same reason.
#
# `PATCH /api/v1/teams/:team_id/issues/:id` is one action serving field edits, lane changes,
# reparenting and labels, exactly as the web form is, so the same rule applies: **at most one
# event per feature_id**, with issue-edit gated on a residual change set. Different feature_ids
# are not double counting (taxonomy §9 is per (feature_id, action) pair) — an MCP `update_issue`
# that retitles an issue and moves it to Done exercises two features and should say so.
#
# It is shorter than the web concern because the JSON API is: there are no multipart uploads, so
# no issue-attachment, and no preloaded @lanes, so lane_move pays its own one-row pluck.
module VektisApiIssueTracking
  extend ActiveSupport::Concern

  included do
    # Must run after set_issue and before assign_attributes — label_ids are rewritten during the
    # assignment, so the before-state has to be captured while it still exists.
    before_action :capture_tracked_label_ids, only: :update
  end

  private

  # The issue's own team, not the one in the path. They are identical here — set_issue scopes off
  # current_team — but an event about an issue belongs to the tenant that owns it, and saying so
  # means a mismatch could never misfile one.
  def tracked_team
    @issue&.team || current_team
  end

  def capture_tracked_label_ids
    @tracked_label_ids = @issue&.label_ids&.sort
  end

  def track_api_issue_created(issue)
    track_api_feature('issue-create', 'create', **issue_shape(issue))
    track_api_feature('sub-issue', 'link', entity: 'issue') if issue.parent_issue_id.present?
    track_api_labels_applied(issue.label_ids.size)
  end

  # Between zero and four events, each owning a different feature_id. A save that changed nothing
  # emits nothing.
  def track_api_issue_updated
    track_api_issue_workflow
    track_api_issue_parent
    track_api_issue_labels
    track_api_issue_edit
  end

  def track_api_issue_workflow
    return unless @issue.saved_change_to_lane_id?

    track_api_feature('issue-workflow', Vektis::IssueProperties.workflow_action(@issue),
                      **Vektis::IssueProperties.lane_move(@issue),
                      **issue_shape(@issue))
  end

  # A -> B reparenting is one `link`; B -> nil is one `unlink`.
  def track_api_issue_parent
    return unless @issue.saved_change_to_parent_issue_id?

    track_api_feature('sub-issue', @issue.parent_issue_id.present? ? 'link' : 'unlink',
                      entity: 'issue')
  end

  def track_api_issue_labels
    return if @tracked_label_ids.nil?

    current = @issue.label_ids.sort
    track_api_labels_applied((current - @tracked_label_ids).size)
    track_api_labels_removed((@tracked_label_ids - current).size)
  end

  def track_api_labels_applied(count)
    track_api_feature('issue-label', 'apply', entity: 'issue', count: count) if count.positive?
  end

  def track_api_labels_removed(count)
    track_api_feature('issue-label', 'remove', entity: 'issue', count: count) if count.positive?
  end

  def track_api_issue_edit
    return unless @issue.saved_changes.keys.intersect?(Vektis::IssueProperties::EDIT_FIELDS)

    track_api_feature('issue-edit', 'update', **issue_shape(@issue))
  end
end
