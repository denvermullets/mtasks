class Decision < ApplicationRecord
  belongs_to :team
  belongs_to :project, optional: true
  belongs_to :issue, optional: true
  belongs_to :pinned_by_user, class_name: 'User', optional: true

  validates :hourglass_message_id, presence: true, uniqueness: true
  validates :pinned_at, presence: true
  validates :body_snapshot, presence: true

  scope :active,    -> { where(unpinned_at: nil) }
  scope :unpinned,  -> { where.not(unpinned_at: nil) }
end
