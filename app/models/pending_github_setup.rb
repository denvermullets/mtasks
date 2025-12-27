class PendingGithubSetup < ApplicationRecord
  belongs_to :workspace

  validates :installation_id, presence: true
  validates :expires_at, presence: true

  # Find pending setups that haven't expired yet
  scope :active, -> { where('expires_at > ?', Time.current) }

  # Create a pending setup with automatic expiry
  # Note: This record should be deleted immediately after the installation is created.
  # The expiry is just a safety net for abandoned setups (user never completes flow).
  def self.create_for_workspace!(workspace:, installation_id:, expires_in: 5.minutes)
    create!(
      workspace: workspace,
      installation_id: installation_id,
      expires_at: expires_in.from_now
    )
  end

  # Check if this pending setup has expired
  def expired?
    expires_at <= Time.current
  end
end
