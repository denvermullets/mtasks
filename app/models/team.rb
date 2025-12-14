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

  # Callbacks
  after_create :create_default_lanes

  # Generate next issue number for this team
  def next_issue_number
    increment!(:issue_counter)
    issue_counter
  end

  private

  def create_default_lanes
    default_lanes = [
      { name: "Backlog", position: 0, color: "#94a3b8" },
      { name: "In Progress", position: 1, color: "#3b82f6" },
      { name: "Done", position: 2, color: "#22c55e" },
      { name: "Cancelled", position: 3, color: "#ef4444" }
    ]

    default_lanes.each do |lane_attrs|
      lanes.create!(lane_attrs)
    end
  end
end
