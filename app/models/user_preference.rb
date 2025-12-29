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
    assign_attributes(default_attributes.except(*attributes.keys))
  end

  def default_attributes
    {
      view_mode: 'board',
      group_by: 'status',
      sub_group_by: 'none',
      order_by: 'manual',
      show_sub_issues: true,
      show_empty_groups: false,
      show_empty_rows: false,
      completed_filter: '',
      visible_properties: DEFAULT_VISIBLE_PROPERTIES
    }
  end

  def visible_properties_array
    props = (visible_properties || []).select { |p| AVAILABLE_PROPERTIES.include?(p) }
    props.empty? ? DEFAULT_VISIBLE_PROPERTIES : props
  end

  def self.for_user_and_team(user, team)
    find_or_create_by(user: user, team: team)
  end
end
