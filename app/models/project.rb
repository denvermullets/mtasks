class Project < ApplicationRecord
  belongs_to :team
  belongs_to :milestone, optional: true
  has_many :issues, dependent: :nullify
  has_many_attached :files

  validates :name, presence: true
end
