class WebhookDelivery < ApplicationRecord
  SOURCES = %w[github hourglass].freeze

  validates :source, inclusion: { in: SOURCES }
  validates :delivery_id, presence: true, uniqueness: { scope: :source }
  validates :event_type, presence: true
  validates :received_at, presence: true

  scope :unprocessed, -> { where(processed_at: nil) }
end
