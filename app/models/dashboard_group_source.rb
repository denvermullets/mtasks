class DashboardGroupSource < ApplicationRecord
  SOURCE_TYPES = %w[Team Project].freeze

  # Associations
  belongs_to :dashboard_group
  belongs_to :source, polymorphic: true

  # Validations
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :source_id, uniqueness: { scope: %i[dashboard_group_id source_type] }
end
