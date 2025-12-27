class PendingGithubSetup < ApplicationRecord
  belongs_to :team

  validates :installation_id, presence: true
  validates :expires_at, presence: true

  # Find pending setups that haven't expired yet
  scope :active, -> { where('expires_at > ?', Time.current) }

  # Create a pending setup with automatic expiry
  # Note: This record should be deleted immediately after the integration is created.
  # The expiry is just a safety net for abandoned setups (user never completes flow).
  def self.create_for_team!(team:, installation_id:, expires_in: 5.minutes)
    create!(
      team: team,
      installation_id: installation_id,
      expires_at: expires_in.from_now
    )
  end

  # Check if this pending setup has expired
  def expired?
    expires_at <= Time.current
  end
end
