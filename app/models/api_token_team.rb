class ApiTokenTeam < ApplicationRecord
  belongs_to :api_token
  belongs_to :team

  validates :team_id, uniqueness: { scope: :api_token_id }
end
