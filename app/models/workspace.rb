class Workspace < ApplicationRecord
  # Associations
  belongs_to :owner, class_name: 'User'
  has_many :teams, dependent: :destroy

  # Validations
  validates :name, presence: true
end
