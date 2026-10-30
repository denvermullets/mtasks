class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: 'User'
  belongs_to :issue
  belongs_to :comment, optional: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc).limit(50) }

  # Marks every unread notification in the current scope read and returns how many changed. It sets
  # updated_at as well because update_all skips timestamps, and the API inbox's ETag and
  # `updated_since` feed both key off it. `before` leaves anything created after that time unread.
  def self.mark_all_read!(before: nil)
    now = Time.current
    pending = unread
    pending = pending.where(created_at: ..before) if before
    pending.update_all(read_at: now, updated_at: now)
  end

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end
end
