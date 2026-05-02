class Workspace < ApplicationRecord
  # Associations
  belongs_to :owner, class_name: 'User'
  has_many :teams, dependent: :destroy
  has_many :github_installations, dependent: :destroy
  has_many :github_repository_subscriptions, through: :teams

  # Validations
  validates :name, presence: true

  # Helper method to get the active GitHub installation (should only be one per workspace)
  def github_installation
    github_installations.active.first
  end
end
