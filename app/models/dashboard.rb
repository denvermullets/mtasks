class Dashboard < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :groups, -> { order(:position, :id) }, class_name: 'DashboardGroup', dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 80 }

  # Scopes
  scope :ordered, -> { order(:position, :id) }
end
