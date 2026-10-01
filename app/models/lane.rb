class Lane < ApplicationRecord
  # Linear-style workflow categories. The category, not the lane name, decides an issue's
  # started/completed/canceled timestamps, so several lanes can share one (e.g. QA Verified and
  # Production deployed both completed).
  CATEGORIES = {
    backlog: 'backlog',
    unstarted: 'unstarted',
    started: 'started',
    completed: 'completed',
    canceled: 'canceled'
  }.freeze
  CLOSED_CATEGORIES = %w[completed canceled].freeze

  belongs_to :team
  has_many :issues, dependent: :restrict_with_error

  enum :category, CATEGORIES, validate: true

  validates :name, presence: true
  validates :position, presence: true

  default_scope { order(position: :asc) }

  scope :closed, -> { where(category: CLOSED_CATEGORIES) }

  def closed?
    category.in?(CLOSED_CATEGORIES)
  end
end
