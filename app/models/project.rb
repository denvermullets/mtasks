class Project < ApplicationRecord
  belongs_to :team
  belongs_to :milestone, optional: true
  has_many :issues, dependent: :nullify

  validates :name, presence: true
end
