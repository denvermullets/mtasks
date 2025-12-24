class PullRequest < ApplicationRecord
  belongs_to :github_integration
  has_many :issue_pull_requests, dependent: :destroy
  has_many :issues, through: :issue_pull_requests

  validates :pr_number, presence: true, uniqueness: { scope: :github_integration_id }
  validates :github_integration_id, presence: true

  scope :open, -> { where(state: 'open') }
  scope :closed, -> { where(state: 'closed') }
  scope :merged, -> { where(merged: true) }
  scope :recent, -> { order(github_created_at: :desc) }

  def status_badge_color
    return 'green' if state == 'open'
    return 'purple' if merged?

    'red'
  end

  def display_status
    return 'Merged' if merged?
    return 'Open' if state == 'open'

    'Closed'
  end
end
