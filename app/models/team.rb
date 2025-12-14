class Team < ApplicationRecord
  # Associations
  belongs_to :workspace
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships
  has_many :lanes, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :milestones, dependent: :destroy
  has_many :issues, dependent: :destroy
  has_many :labels, dependent: :destroy

  # Validations
  validates :name, presence: true

  # Generate next issue number for this team
  def next_issue_number
    increment!(:issue_counter)
    issue_counter
  end
end
