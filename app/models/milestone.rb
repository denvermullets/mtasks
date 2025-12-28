class Milestone < ApplicationRecord
  belongs_to :team
  has_many :projects, dependent: :nullify
  has_many :issues, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :team_id, case_sensitive: false }

  scope :by_due_date, -> { order(:due_date) }

  def progress_percentage
    return 0 if issues.none?

    completed = issues.where.not(completed_at: nil).count
    (completed.to_f / issues.count * 100).round
  end

  def behind_schedule?
    return false unless due_date

    progress_percentage < expected_progress_percentage
  end

  def expected_progress_percentage
    return 0 unless start_date && due_date
    return 100 if Date.current >= due_date

    total_days = (due_date - start_date).to_i
    elapsed_days = (Date.current - start_date).to_i
    return 0 if elapsed_days <= 0

    [(elapsed_days.to_f / total_days * 100).round, 100].min
  end

  def status_color
    return '#6b7280' unless due_date

    if Date.current > due_date
      '#ef4444'  # Red - past due
    elsif due_date <= Date.current + 7.days
      '#f59e0b'  # Orange - due within 7 days
    elsif behind_schedule?
      '#f59e0b'  # Orange - behind schedule based on progress
    else
      '#10b981'  # Green - on track
    end
  end

  def formatted_due_date
    due_date&.strftime('%b %d')
  end

  def issue_count
    issues.count
  end
end
