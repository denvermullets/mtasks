class IssuePullRequest < ApplicationRecord
  belongs_to :issue
  belongs_to :pull_request

  validates :issue_id, presence: true, uniqueness: { scope: :pull_request_id }
  validates :pull_request_id, presence: true
end
