class UserPreference < ApplicationRecord
  belongs_to :user
  belongs_to :team

  validates :view_mode, inclusion: { in: %w[board list] }
  validates :group_by, inclusion: {
    in: %w[none status assignee project priority label parent_issue]
  }
  validates :sub_group_by, inclusion: {
    in: %w[none status priority assignee project]
  }, allow_nil: true
  validates :order_by, inclusion: {
    in: %w[manual priority due_date created_at updated_at]
  }

  AVAILABLE_PROPERTIES = %w[
    id status assignee priority due_date project milestone
    estimate labels links time_in_status created_at updated_at
    pull_requests_and_commits
  ].freeze

  def visible_properties_array
    (visible_properties || []).select { |p| AVAILABLE_PROPERTIES.include?(p) }
  end

  def self.for_user_and_team(user, team)
    find_or_create_by(user: user, team: team)
  end
end
