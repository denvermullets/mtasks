class PrAutomationRule < ApplicationRecord
  TRIGGERS = %w[pr_opened pr_merged pr_closed].freeze

  belongs_to :github_repository_subscription
  belongs_to :lane

  validates :trigger, presence: true, inclusion: { in: TRIGGERS },
                      uniqueness: { scope: %i[github_repository_subscription_id branch_pattern] }
  validates :branch_pattern, presence: true, if: -> { trigger == 'pr_merged' }
  validates :branch_pattern, absence: true, unless: -> { trigger == 'pr_merged' }
  validate :lane_belongs_to_same_team

  private

  def lane_belongs_to_same_team
    return unless github_repository_subscription && lane

    return if github_repository_subscription.team_id == lane.team_id

    errors.add(:lane, 'must belong to the same team as the subscription')
  end
end
