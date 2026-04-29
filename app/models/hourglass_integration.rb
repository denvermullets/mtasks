class HourglassIntegration < ApplicationRecord
  belongs_to :workspace
  belongs_to :connected_by_user, class_name: 'User', optional: true
  has_many :hourglass_channel_subscriptions, dependent: :destroy

  validates :hourglass_server_id, presence: true
  validates :base_url, presence: true
  validates :hourglass_server_id, uniqueness: { scope: :workspace_id }

  scope :active, -> { where(active: true) }
end
