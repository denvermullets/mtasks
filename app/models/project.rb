class Project < ApplicationRecord
  STATUSES = %w[backlog started paused completed cancelled].freeze

  enum :priority, { urgent: 0, high: 1, medium: 2, low: 3, no_priority: 4 }

  belongs_to :team
  belongs_to :milestone, optional: true
  belongs_to :lead, class_name: 'User', optional: true
  has_many :issues, dependent: :nullify
  has_many :project_labels, dependent: :destroy
  has_many :labels, through: :project_labels
  has_many_attached :files

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
end
