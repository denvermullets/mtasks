class HourglassChannelSubscription < ApplicationRecord
  belongs_to :hourglass_integration
  belongs_to :team

  validates :hourglass_server_id, presence: true
  validates :team_id, uniqueness: { scope: :hourglass_integration_id }
  validate :team_in_integration_workspace

  scope :active, -> { where(active: true) }

  private

  def team_in_integration_workspace
    return if team.nil? || hourglass_integration.nil?
    return if team.workspace_id == hourglass_integration.workspace_id

    errors.add(:team, "must belong to the integration's workspace")
  end
end
