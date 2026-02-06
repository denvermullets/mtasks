class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: 'User'
  belongs_to :issue
  belongs_to :comment, optional: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc).limit(50) }

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end
end
