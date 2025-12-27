class GithubInstallation < ApplicationRecord
  belongs_to :workspace
  has_many :github_repository_subscriptions, dependent: :destroy
  has_many :teams, through: :github_repository_subscriptions
  has_many :pull_requests, through: :github_repository_subscriptions

  validates :installation_id, presence: true, uniqueness: true
  validates :workspace_id, presence: true

  scope :active, -> { where(active: true) }

  # Generate fresh installation access token
  def access_token
    GithubApp.installation_token(installation_id)
  end
end
