class DashboardGroup < ApplicationRecord
  # Associations
  belongs_to :dashboard
  has_many :sources, class_name: 'DashboardGroupSource', dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :color, format: { with: /\A#\h{6}\z/ }

  def team_ids
    sources.where(source_type: 'Team').pluck(:source_id)
  end

  def project_ids
    sources.where(source_type: 'Project').pluck(:source_id)
  end
end
