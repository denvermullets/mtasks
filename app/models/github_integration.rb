class GithubIntegration < ApplicationRecord
  belongs_to :team
  has_many :pull_requests, dependent: :destroy

  validates :github_repo_full_name, presence: true
  validates :installation_id, presence: true
  validates :team_id, uniqueness: { scope: %i[installation_id github_repo_full_name] }

  def repo_owner
    github_repo_full_name&.split('/')&.first
  end

  def repo_name
    github_repo_full_name&.split('/')&.last
  end

  # Generate a fresh installation access token when needed
  def access_token
    GithubApp.installation_token(installation_id)
  end
end
