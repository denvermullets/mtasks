class Issue < ApplicationRecord
  has_paper_trail only: %i[title description lane_id priority estimate due_date assignee_id project_id
                           parent_issue_id]

  enum :priority, { urgent: 0, high: 1, medium: 2, low: 3, no_priority: 4 }

  # Associations
  belongs_to :team
  belongs_to :lane
  belongs_to :project, optional: true
  belongs_to :creator, class_name: 'User', optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :parent_issue, class_name: 'Issue', optional: true
  has_many :sub_issues, class_name: 'Issue', foreign_key: :parent_issue_id, dependent: :nullify
  has_many :issue_labels, dependent: :destroy
  has_many :labels, through: :issue_labels
  has_many :comments, dependent: :destroy
  has_many :issue_pull_requests, dependent: :destroy
  has_many :pull_requests, through: :issue_pull_requests
  has_many :notifications, dependent: :destroy
  has_many :outgoing_references, class_name: 'IssueReference', foreign_key: :source_issue_id, dependent: :destroy
  has_many :incoming_references, class_name: 'IssueReference', foreign_key: :referenced_issue_id, dependent: :destroy
  has_many :blocking_dependencies, class_name: 'IssueDependency', foreign_key: :blocking_issue_id, dependent: :destroy
  has_many :blocked_dependencies, class_name: 'IssueDependency', foreign_key: :blocked_issue_id, dependent: :destroy
  has_many :blocked_issues, through: :blocking_dependencies, source: :blocked_issue
  has_many :blocking_issues, through: :blocked_dependencies, source: :blocking_issue
  has_many_attached :files

  # Validations
  validates :title, presence: true
  validates :team_number, presence: true, uniqueness: { scope: :team_id }

  # Callbacks
  before_validation :assign_team_number, on: :create
  after_create_commit :enqueue_velocity_recalculation!

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

  def completed?
    completed_at.present?
  end

  def time_in_current_status
    last_lane_change = versions.where('object_changes::text LIKE ?', '%"lane_id"%').order(:created_at).last
    started_at = last_lane_change&.created_at || created_at
    Time.current - started_at
  end

  CANCELED_LANE_NAMES = %w[cancelled canceled].freeze

  def apply_lane_timestamps!
    return unless lane_id_changed?

    new_lane_name = Lane.find_by(id: lane_id)&.name&.downcase
    apply_completion_timestamp(new_lane_name)
    apply_cancellation_timestamp(new_lane_name)
  end

  def apply_completion_timestamp(new_lane_name)
    if new_lane_name == 'done'
      self.completed_at = Time.current
    elsif completed_at.present?
      self.completed_at = nil
    end
  end

  def apply_cancellation_timestamp(new_lane_name)
    if CANCELED_LANE_NAMES.include?(new_lane_name)
      self.canceled_at = Time.current
    elsif canceled_at.present?
      self.canceled_at = nil
    end
  end

  def remove_blocking_dependencies!
    blocking_dependencies.destroy_all if completed?
  end

  def enqueue_velocity_recalculation!
    return unless saved_change_to_project_id? || saved_change_to_completed_at? || saved_change_to_archived_at?

    ProjectVelocityJob.perform_later(project_id) if project_id.present?
    return unless saved_change_to_project_id? && project_id_before_last_save.present?

    ProjectVelocityJob.perform_later(project_id_before_last_save)
  end

  private

  def assign_team_number
    return if team_number.present?

    self.team_number = team.next_issue_number
  end
end
