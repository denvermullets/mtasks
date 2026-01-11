class Comment < ApplicationRecord
  MAX_NESTING_DEPTH = 4

  belongs_to :issue
  belongs_to :user
  belongs_to :parent, class_name: 'Comment', optional: true
  has_many :replies, class_name: 'Comment', foreign_key: :parent_id, dependent: :destroy

  validates :body, presence: true

  scope :top_level, -> { where(parent_id: nil) }

  def depth
    return 0 if parent_id.nil?

    parent.depth + 1
  end

  def can_reply?
    depth < MAX_NESTING_DEPTH
  end
end
