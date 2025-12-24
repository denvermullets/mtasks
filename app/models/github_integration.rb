class GithubIntegration < ApplicationRecord
  belongs_to :team
  has_many :pull_requests, dependent: :destroy

  encrypts :access_token
  encrypts :refresh_token

  validates :github_repo_full_name, presence: true
  validates :team_id, uniqueness: true

  def token_expired?
    return false if token_expires_at.nil?

    token_expires_at < Time.current
  end

  def repo_owner
    github_repo_full_name&.split('/')&.first
  end

  def repo_name
    github_repo_full_name&.split('/')&.last
  end
end
