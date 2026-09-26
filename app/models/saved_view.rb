# A named snapshot of the issues board's URL state (filters + display options) for one team.
# The board keeps all of that in the query string, so a view is just that query replayed.
class SavedView < ApplicationRecord
  # Everything DisplayOptionsService and the search box read; anything else in the URL is dropped.
  QUERY_KEYS = %w[
    view_mode group_by sub_group_by order_by completed_filter visible_properties
    show_sub_issues show_empty_groups show_empty_rows show_dependencies
    lane_ids assignee_ids creator_ids label_ids project_ids priority q
  ].freeze

  # Associations
  belongs_to :user
  belongs_to :team

  # Validations
  validates :name, presence: true, length: { maximum: 80 }

  # Scopes
  scope :ordered, -> { order(:position, :id) }

  # "?group_by=assignee&lane_ids=1,2" -> { "group_by" => "assignee", "lane_ids" => "1,2" }
  def self.query_from(query_string)
    Rack::Utils.parse_query(query_string.to_s.delete_prefix('?'))
               .slice(*QUERY_KEYS)
               .transform_values { |value| Array(value).last.to_s }
  end

  def path
    base = "/teams/#{team_id}/issues"
    query.present? ? "#{base}?#{query.to_query}" : base
  end
end
