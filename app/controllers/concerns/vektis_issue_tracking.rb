# The VEK-584 call sites for IssuesController, kept out of the controller because the rule is
# issue-specific and long enough to bury the actions.
#
# IssuesController#update is one action serving field edits, lane changes, reparenting, labels
# and uploads — lane_picker_controller.js PATCHes { issue: { lane_id } } to the same place the
# edit form posts. The rule is therefore **at most one event per feature_id**, with issue-edit
# gated on a residual change set. Different feature_ids are not double counting (taxonomy §9 is
# per (feature_id, action) pair): an edit-form save that changes the title and moves the lane
# exercises two features and should say so.
module VektisIssueTracking
  extend ActiveSupport::Concern

  included do
    # Must run after set_issue, which is why IssuesController includes this module below its
    # before_action block — label_ids are written during assign_attributes, so the before-state
    # has to be read earlier than the success branch.
    before_action :capture_tracked_label_ids, only: :update
  end

  # Shared with Api::V1's tracking concern, which saves the same issues from a different surface.
  EDIT_FIELDS = Vektis::IssueProperties::EDIT_FIELDS

  private

  # The issue's own team, not the session's. They are normally identical — IssuesController scopes
  # every @issue off current_team — but an event about an issue belongs to the tenant that owns the
  # issue, and saying so here means a stale session cannot misfile one.
  def tracked_team
    @issue&.team || current_team
  end

  def capture_tracked_label_ids
    @tracked_label_ids = @issue&.label_ids&.sort
  end

  def track_issue_created
    track_feature('issue-create', 'create', **issue_shape(@issue))
    track_feature('sub-issue', 'link', entity: 'issue') if @issue.parent_issue_id.present?
    track_labels_applied(@issue.label_ids.size)
    track_issue_attachments
  end

  # Between zero and five events, each owning a different feature_id. A save that changed nothing
  # emits nothing.
  def track_issue_updated
    track_issue_workflow
    track_issue_parent
    track_issue_labels
    track_issue_attachments
    track_issue_edit
  end

  def track_issue_deleted(issue)
    track_feature('issue-delete', 'delete', **issue_shape(issue))
  end

  def track_issue_workflow
    return unless @issue.saved_change_to_lane_id?

    action = Vektis::IssueProperties.workflow_action(@issue)
    # @lanes is the relation load_form_collections already built and update.turbo_stream.erb
    # already renders, so the position lookup costs no extra query.
    track_feature('issue-workflow', action,
                  **Vektis::IssueProperties.lane_move(@issue, lanes: @lanes),
                  **issue_shape(@issue))
  end

  # A -> B reparenting is one `link`; B -> nil is one `unlink`.
  def track_issue_parent
    return unless @issue.saved_change_to_parent_issue_id?

    track_feature('sub-issue', @issue.parent_issue_id.present? ? 'link' : 'unlink', entity: 'issue')
  end

  # The edit form can change labels without touching IssueLabelsController. `count` is what
  # separates a bulk form save from a single picker gesture on the same (feature_id, action).
  def track_issue_labels
    return if @tracked_label_ids.nil?

    current = @issue.label_ids.sort
    track_labels_applied((current - @tracked_label_ids).size)
    track_labels_removed((@tracked_label_ids - current).size)
  end

  def track_labels_applied(count)
    track_feature('issue-label', 'apply', entity: 'issue', count: count) if count.positive?
  end

  def track_labels_removed(count)
    track_feature('issue-label', 'remove', entity: 'issue', count: count) if count.positive?
  end

  def track_issue_attachments
    count = uploaded_file_count(params.dig(:issue, :files))
    return unless count.positive?

    track_feature('issue-attachment', 'create', entity: 'issue', count: count)
  end

  def track_issue_edit
    return unless @issue.saved_changes.keys.intersect?(EDIT_FIELDS)

    track_feature('issue-edit', 'update', **issue_shape(@issue))
  end
end
