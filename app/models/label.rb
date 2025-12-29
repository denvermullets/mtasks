class Label < ApplicationRecord
  belongs_to :team
  has_many :issue_labels, dependent: :destroy
  has_many :issues, through: :issue_labels

  validates :name, presence: true, uniqueness: { scope: :team_id, case_sensitive: false }
  validates :color, presence: true

  # Scope to order labels by usage count (most used first)
  scope :by_usage, lambda {
    left_joins(:issue_labels)
      .group(:id)
      .order(Arel.sql('COUNT(issue_labels.id) DESC'))
  }

  # Scope to get frequently used labels (top 5 with at least 1 use)
  scope :frequently_used, lambda {
    by_usage
      .having('COUNT(issue_labels.id) > 0')
      .limit(5)
  }

  # Calculate usage count for this label
  def usage_count
    issue_labels.count
  end

  # Generate a random color from a predefined palette
  def self.random_color
    ['#ef4444', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6', '#ec4899'].sample
  end
end
