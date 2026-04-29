class Comment < ApplicationRecord
  MAX_NESTING_DEPTH = 4

  belongs_to :issue, optional: true
  belongs_to :project, optional: true
  belongs_to :user
  belongs_to :parent, class_name: 'Comment', optional: true
  has_many :replies, class_name: 'Comment', foreign_key: :parent_id, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many_attached :files

  validate :body_or_files_present
  validate :exactly_one_owner

  scope :top_level, -> { where(parent_id: nil) }

  def depth
    return 0 if parent_id.nil?

    parent.depth + 1
  end

  def can_reply?
    depth < MAX_NESTING_DEPTH
  end

  private

  def body_or_files_present
    return if body.present? || files.attached?

    errors.add(:base, 'Comment must have text or an attachment')
  end

  def exactly_one_owner
    return if issue_id.present? ^ project_id.present?

    errors.add(:base, 'Comment must belong to exactly one of issue or project')
  end
end
