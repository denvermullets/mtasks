class IssueReference < ApplicationRecord
  belongs_to :source_issue, class_name: 'Issue'
  belongs_to :referenced_issue, class_name: 'Issue'
  belongs_to :user

  validates :source_type, presence: true, inclusion: { in: %w[description comment] }
  validates :referenced_issue_id, uniqueness: { scope: %i[source_issue_id source_type] }
  validate :cannot_reference_self

  private

  def cannot_reference_self
    return unless source_issue_id == referenced_issue_id

    errors.add(:base, 'An issue cannot reference itself')
  end
end
