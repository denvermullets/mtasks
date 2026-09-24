# A template that files a fresh issue on a schedule ("deploy every Friday"). Each spawned issue is an
# ordinary issue that someone has to move to Done — the template only decides when the next one appears.
#
# next_run_on is a calendar date in the template's own time_zone (defaulted from the creator's
# preference), so "every Friday" means Friday where the team is. RecurringIssuesJob sweeps hourly.
class RecurringIssue < ApplicationRecord
  enum :frequency, { daily: 0, weekly: 1, monthly: 2 }
  enum :priority, Issue.priorities

  belongs_to :team
  belongs_to :creator, class_name: 'User', optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :project, optional: true
  belongs_to :lane, optional: true
  has_many :issues, dependent: :nullify

  validates :title, :next_run_on, presence: true
  validates :interval, numericality: { only_integer: true, in: 1..365 }
  validates :weekday, inclusion: { in: 0..6 }, if: :weekly?
  validates :day_of_month, inclusion: { in: 1..31 }, if: :monthly?
  validates :time_zone, inclusion: { in: ->(_) { ActiveSupport::TimeZone.all.map(&:name) } }

  scope :active, -> { where(active: true) }
  # Coarse SQL cut: no zone is more than a day ahead of UTC. spawn! makes the exact per-zone check.
  scope :due_soon, -> { active.where(next_run_on: ..Time.now.utc.to_date.next_day) }

  # Snaps next_run_on to the first occurrence on or after start_date (never before today, so resuming
  # a paused schedule doesn't back-file). Called explicitly by whoever edits the schedule, since
  # changing the pattern invalidates whatever date was stored before.
  def schedule_from(start_date, today: local_today)
    self.next_run_on = start_date && first_occurrence_on_or_after([start_date, today].max)
  end

  # Files the issue for the current occurrence and moves next_run_on past today. Missed occurrences
  # (downtime, a paused template) are skipped rather than back-filled: one issue per sweep.
  def spawn!(today: local_today)
    with_lock do
      next unless active? && next_run_on <= today

      issue = team.issues.create!(issue_attributes)
      update!(next_run_on: next_occurrence_after(today), last_run_at: Time.current)
      issue
    end
  end

  def local_today
    Time.current.in_time_zone(time_zone.presence || 'UTC').to_date
  end

  def schedule_summary
    unit = { 'daily' => 'day', 'weekly' => 'week', 'monthly' => 'month' }.fetch(frequency)
    every = interval == 1 ? "Every #{unit}" : "Every #{interval} #{unit.pluralize}"

    case frequency
    when 'weekly' then "#{every} on #{Date::DAYNAMES[weekday]}"
    when 'monthly' then "#{every} on the #{day_of_month.ordinalize}"
    else every
    end
  end

  private

  def issue_attributes
    {
      title: title,
      description: description,
      priority: priority,
      creator: creator,
      assignee: (assignee if assignee && team.users.exists?(assignee.id)),
      project: project,
      lane: lane || team.lanes.first,
      label_ids: team.labels.where(id: label_ids).ids,
      recurring_issue: self
    }
  end

  def next_occurrence_after(today)
    date = step(next_run_on)
    date = step(date) while date <= today
    date
  end

  def step(date)
    case frequency
    when 'daily' then date + interval.days
    when 'weekly' then date + interval.weeks
    else clamp_to_day_of_month(date >> interval)
    end
  end

  def first_occurrence_on_or_after(date)
    case frequency
    when 'daily' then date
    when 'weekly' then date + ((weekday.to_i - date.wday) % 7).days
    else
      candidate = clamp_to_day_of_month(date)
      candidate < date ? clamp_to_day_of_month(date.next_month) : candidate
    end
  end

  # The 31st in a 30-day month lands on the 30th; the month after goes back to the 31st.
  def clamp_to_day_of_month(date)
    date.change(day: [day_of_month.to_i, date.end_of_month.day].min)
  end
end
