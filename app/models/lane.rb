class Lane < ApplicationRecord
  belongs_to :team
  has_many :issues, dependent: :restrict_with_error

  validates :name, presence: true
  validates :position, presence: true

  default_scope { order(position: :asc) }
end
