class HourglassChannelSubscription < ApplicationRecord
  belongs_to :hourglass_integration
  belongs_to :team

  validates :hourglass_server_id, presence: true
  validates :team_id, uniqueness: { scope: :hourglass_integration_id }

  scope :active, -> { where(active: true) }
end
