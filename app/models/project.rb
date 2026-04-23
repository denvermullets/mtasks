class Project < ApplicationRecord
  STATUSES = %w[backlog started paused completed cancelled].freeze
  ROADMAP_COMMITMENTS = %w[now next later].freeze

  enum :priority, { urgent: 0, high: 1, medium: 2, low: 3, no_priority: 4 }

  belongs_to :team
  belongs_to :lead, class_name: 'User', optional: true
  has_many :issues, dependent: :nullify
  has_many :project_labels, dependent: :destroy
  has_many :labels, through: :project_labels
  has_many_attached :files

  scope :on_roadmap, -> { where.not(roadmap_commitment: nil) }
  scope :in_commitment, lambda { |commitment|
    where(roadmap_commitment: commitment).order(Arel.sql('due_date ASC NULLS LAST'), :id)
  }

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  validates :roadmap_commitment, inclusion: { in: ROADMAP_COMMITMENTS }, allow_nil: true

  normalizes :roadmap_commitment, with: lambda(&:presence)

  def recalculate_velocity!
    update_columns(
      velocity_score: issues.not_archived.where('completed_at >= ?', 14.days.ago).count,
      completed_issues_count: issues.not_archived.where.not(completed_at: nil).count,
      total_issues_count: issues.not_archived.count
    )
  end

  def progress_percentage
    return 0 if total_issues_count.zero?

    (completed_issues_count.to_f / total_issues_count * 100).round
  end

  def behind_schedule?
    return false unless start_date && due_date && due_date > start_date

    total_days = (due_date - start_date).to_f
    elapsed_days = ([Date.current, due_date].min - start_date).to_f
    return false if elapsed_days <= 0

    expected = (elapsed_days / total_days * total_issues_count).round
    completed_issues_count < expected
  end

  def progress_chart_data
    project_issues = issues.not_archived
    return [] if project_issues.none?

    issue_dates = pluck_issue_dates(project_issues)
    sampled_days = chart_date_range(project_issues)

    sampled_days.map { |day| daily_snapshot(day, issue_dates) }
  end

  def expected_progress_line
    return nil unless start_date && due_date && total_issues_count.positive?

    [
      { date: start_date.iso8601, value: 0 },
      { date: due_date.iso8601, value: total_issues_count }
    ]
  end

  private

  def pluck_issue_dates(project_issues)
    project_issues.pluck(:created_at, :started_at, :completed_at).map do |created, started, completed|
      { created: created&.to_date, started: started&.to_date, completed: completed&.to_date }
    end
  end

  def chart_date_range(project_issues)
    chart_start = start_date || project_issues.minimum(:created_at)&.to_date || created_at.to_date
    chart_end = [Date.current, due_date].compact.max
    days = (chart_start..chart_end).to_a
    sample_days(days, [days.length, 60].min)
  end

  def daily_snapshot(day, issue_dates)
    {
      date: day.iso8601,
      scope: issue_dates.count { |d| d[:created] && d[:created] <= day },
      started: issue_dates.count { |d| d[:started] && d[:started] <= day },
      completed: issue_dates.count { |d| d[:completed] && d[:completed] <= day }
    }
  end

  def sample_days(days, target)
    return days if days.length <= target

    step = (days.length - 1).to_f / (target - 1)
    (0...target).map { |i| days[(i * step).round] }.uniq
  end
end
