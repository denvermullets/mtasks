class IssueDependency < ApplicationRecord
  belongs_to :blocking_issue, class_name: 'Issue'
  belongs_to :blocked_issue, class_name: 'Issue'

  validates :blocked_issue_id, uniqueness: { scope: :blocking_issue_id }
  validate :cannot_block_self
  validate :same_team

  private

  def cannot_block_self
    errors.add(:base, 'An issue cannot block itself') if blocking_issue_id == blocked_issue_id
  end

  def same_team
    return unless blocking_issue && blocked_issue

    errors.add(:base, 'Issues must be in the same team') unless blocking_issue.team_id == blocked_issue.team_id
  end
end
