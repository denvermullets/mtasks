class HourglassMessageCache < ApplicationRecord
  self.table_name = 'hourglass_message_cache'

  SOURCES = %w[webhook backfill echo].freeze

  validates :hourglass_message_id, presence: true, uniqueness: true
  validates :hourglass_channel_id, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :posted_at, presence: true

  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :pinned,      -> { where.not(pinned_at: nil) }
end
