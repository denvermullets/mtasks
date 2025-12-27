class GithubRepositorySubscription < ApplicationRecord
  belongs_to :team
  belongs_to :github_installation
  has_many :pull_requests, dependent: :destroy

  validates :team_id, uniqueness: { scope: %i[github_installation_id github_repo_full_name] }
  validates :github_repo_full_name, presence: true

  scope :active, -> { where(active: true) }

  def repo_owner
    github_repo_full_name&.split('/')&.first
  end

  def repo_name
    github_repo_full_name&.split('/')&.last
  end

  # Generate fresh installation access token (delegated to installation)
  def access_token
    github_installation.access_token
  end
end
