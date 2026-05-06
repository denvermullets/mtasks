class TeamMembership < ApplicationRecord
  belongs_to :user
  belongs_to :team

  enum :role, { member: 0, admin: 1 }

  validates :user_id, uniqueness: { scope: :team_id }
end
