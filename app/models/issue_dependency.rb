class IssueDependency < ApplicationRecord
  has_paper_trail

  # blocks:     blocking_issue blocks blocked_issue.
  # relates:    symmetric; blocking_issue is just the source and blocked_issue the target.
  # duplicates: blocking_issue (source) duplicates blocked_issue (target, the canonical issue).
  enum :kind, { blocks: 'blocks', relates: 'relates', duplicates: 'duplicates' }, default: 'blocks'

  belongs_to :blocking_issue, class_name: 'Issue'
  belongs_to :blocked_issue, class_name: 'Issue'

  validates :blocked_issue_id, uniqueness: { scope: :blocking_issue_id }
  validate :cannot_block_self
  validate :same_team
  validate :not_already_linked
  validate :no_blocks_cycle

  # Readers for non-block kinds, where "blocking"/"blocked" don't read naturally.
  def source_issue
    blocking_issue
  end

  def target_issue
    blocked_issue
  end

  private

  def cannot_block_self
    errors.add(:base, 'An issue cannot block itself') if blocking_issue_id == blocked_issue_id
  end

  def same_team
    return unless blocking_issue && blocked_issue

    errors.add(:base, 'Issues must be in the same team') unless blocking_issue.team_id == blocked_issue.team_id
  end

  # One link per pair of issues, in either direction, of any kind. The uniqueness validation
  # covers the forward pair; this covers the reverse.
  def not_already_linked
    return unless blocking_issue_id && blocked_issue_id

    reverse = IssueDependency.where(blocking_issue_id: blocked_issue_id, blocked_issue_id: blocking_issue_id)
    errors.add(:base, 'These issues are already linked') if reverse.where.not(id: id).exists?
  end

  def no_blocks_cycle
    return unless blocks? && blocking_issue_id && blocked_issue_id
    return if blocking_issue_id == blocked_issue_id

    return unless blocks_path?(from: blocked_issue_id, to: blocking_issue_id)

    errors.add(:base, 'Would create a circular dependency')
  end

  # BFS over blocks edges, one query per level. Excludes this row so re-validating a saved link
  # doesn't count its own edge.
  def blocks_path?(from:, to:)
    visited = Set[from]
    frontier = [from]
    while frontier.any?
      next_ids = IssueDependency.blocks.where(blocking_issue_id: frontier).where.not(id: id).pluck(:blocked_issue_id)
      return true if next_ids.include?(to)

      frontier = next_ids.uniq.reject { |issue_id| visited.include?(issue_id) }
      visited.merge(frontier)
    end
    false
  end
end
