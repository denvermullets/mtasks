class Issue < ApplicationRecord
  enum :priority, { urgent: 0, high: 1, medium: 2, low: 3, no_priority: 4 }

  # Associations
  belongs_to :team
  belongs_to :lane
  belongs_to :project, optional: true
  belongs_to :milestone, optional: true
  belongs_to :creator, class_name: 'User', optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :parent_issue, class_name: 'Issue', optional: true
  has_many :sub_issues, class_name: 'Issue', foreign_key: :parent_issue_id, dependent: :nullify
  has_many :issue_labels, dependent: :destroy
  has_many :labels, through: :issue_labels

  # Validations
  validates :title, presence: true
  validates :team_number, presence: true, uniqueness: { scope: :team_id }

  # Callbacks
  before_validation :assign_team_number, on: :create

  # Scopes
  scope :archived, -> { where.not(archived_at: nil) }
  scope :not_archived, -> { where(archived_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :not_completed, -> { where(completed_at: nil) }
  scope :in_progress, -> { where.not(started_at: nil).where(completed_at: nil, canceled_at: nil) }

  def identifier
    "#{team.identifier}-#{team_number}"
  end

  def complete!
    update(completed_at: Time.current)
  end

  def cancel!
    update(canceled_at: Time.current)
  end

  def archive!
    update(archived_at: Time.current)
  end

  def start!
    update(started_at: Time.current) if started_at.nil?
  end

  private

  def assign_team_number
    return if team_number.present?

    self.team_number = team.next_issue_number
  end
end
