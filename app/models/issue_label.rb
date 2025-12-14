class IssueLabel < ApplicationRecord
  belongs_to :issue
  belongs_to :label

  validates :issue_id, uniqueness: { scope: :label_id }
end
