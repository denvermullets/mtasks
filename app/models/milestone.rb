class Milestone < ApplicationRecord
  belongs_to :team
  has_many :projects, dependent: :nullify
  has_many :issues, dependent: :nullify

  validates :name, presence: true

  def progress_percentage
    return 0 if issues.count.zero?
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
end
