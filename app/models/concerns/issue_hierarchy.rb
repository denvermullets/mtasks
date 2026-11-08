# Sub-issues: an issue has at most one parent (parent_issue_id) and any number of sub-issues.
# Nesting depth is unlimited; the validation guards against self-parenting, cross-team parents,
# and cycles. Tree walks go one query per level and keep a visited set, so a legacy cycle in
# the data still terminates.
module IssueHierarchy
  extend ActiveSupport::Concern

  included do
    validate :valid_parent_issue, if: :parent_issue_id_changed?
  end

  # Ids of every issue above this one in its sub-issue chain, nearest first.
  def ancestor_ids
    return [] if parent_issue_id.nil?

    ancestor_ids_from(parent_issue_id) - [id]
  end

  # Ids of every issue below this one.
  def descendant_ids
    visited = Set[id]
    frontier = [id]
    while frontier.any?
      frontier = Issue.where(parent_issue_id: frontier).where.not(id: visited.to_a).pluck(:id)
      visited.merge(frontier)
    end
    visited.to_a - [id]
  end

  # Makes this (new) issue a sub-issue of the team's issue `parent_id`, starting it in the
  # parent's project. A blank or unknown id (including another team's issue) is a no-op.
  def nest_under(parent_id)
    parent = team.issues.find_by(id: parent_id) if parent_id.present?
    return unless parent

    self.parent_issue = parent
    self.project_id ||= parent.project_id
  end

  private

  def valid_parent_issue
    message = parent_issue_error
    errors.add(:parent_issue, message) if message
  end

  def parent_issue_error
    return if parent_issue_id.nil?
    return 'does not exist' if parent_issue.nil?
    return 'must be in the same team' if parent_issue.team_id != team_id
    # A new issue has no sub-issues yet, so it can't be its own parent or close a loop.
    return unless persisted?
    return 'cannot be the issue itself' if parent_issue_id == id

    'would create a circular sub-issue chain' if ancestor_ids_from(parent_issue_id).include?(id)
  end

  # `start_id` followed by each issue above it.
  def ancestor_ids_from(start_id)
    visited = [start_id]
    while (next_id = Issue.where(id: visited.last).pick(:parent_issue_id)) && visited.exclude?(next_id)
      visited << next_id
    end
    visited
  end
end
