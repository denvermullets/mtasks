class UserPreference < ApplicationRecord
  belongs_to :user
  belongs_to :team

  validates :view_mode, inclusion: { in: %w[board list] }
  validates :group_by, inclusion: {
    in: %w[none status assignee project priority label parent_issue milestone]
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

  DEFAULT_VISIBLE_PROPERTIES = %w[
    assignee priority due_date project milestone estimate labels
  ].freeze

  after_initialize :set_defaults, if: :new_record?

  def set_defaults
    self.view_mode ||= 'board'
    self.group_by ||= 'status'
    self.sub_group_by ||= 'none'
    self.order_by ||= 'manual'
    self.show_sub_issues = true if show_sub_issues.nil?
    self.show_empty_groups = false if show_empty_groups.nil?
    self.show_empty_rows = false if show_empty_rows.nil?
    self.completed_filter ||= ''
    self.visible_properties ||= DEFAULT_VISIBLE_PROPERTIES
  end

  def visible_properties_array
    props = (visible_properties || []).select { |p| AVAILABLE_PROPERTIES.include?(p) }
    props.empty? ? DEFAULT_VISIBLE_PROPERTIES : props
  end

  def self.for_user_and_team(user, team)
    find_or_create_by(user: user, team: team)
  end
end
