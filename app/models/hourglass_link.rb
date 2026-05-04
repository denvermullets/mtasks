class HourglassLink < ApplicationRecord
  LINK_TYPES = %w[project_channel issue_thread].freeze

  belongs_to :team
  belongs_to :mtasks_project, class_name: 'Project', optional: true
  belongs_to :mtasks_issue, class_name: 'Issue', optional: true
  belongs_to :created_by_user, class_name: 'User', optional: true
  belongs_to :hourglass_integration, optional: true

  enum :status, { active: 'active', broken: 'broken' }, default: 'active'

  validates :link_type, inclusion: { in: LINK_TYPES }
  validate :columns_match_link_type
  validates :mtasks_project_id,
            uniqueness: { conditions: -> { where(link_type: 'project_channel') } },
            if: -> { link_type == 'project_channel' && mtasks_project_id.present? }
  validates :hourglass_channel_id,
            uniqueness: { conditions: -> { where(link_type: 'project_channel') } },
            if: -> { link_type == 'project_channel' && hourglass_channel_id.present? }

  scope :project_channel, -> { where(link_type: 'project_channel') }
  scope :issue_thread,    -> { where(link_type: 'issue_thread') }
  scope :for_project,     ->(project) { project_channel.where(mtasks_project_id: project.id) }
  scope :for_issue,       ->(issue) { issue_thread.where(mtasks_issue_id: issue.id) }

  private

  def columns_match_link_type
    case link_type
    when 'project_channel' then validate_project_channel_columns
    when 'issue_thread'    then validate_issue_thread_columns
    end
  end

  def validate_project_channel_columns
    unless mtasks_project_id.present? && hourglass_channel_id.present?
      errors.add(:base, 'project_channel link requires mtasks_project_id and hourglass_channel_id')
    end
    return if mtasks_issue_id.blank? && hourglass_thread_id.blank?

    errors.add(:base, 'project_channel link must not set mtasks_issue_id or hourglass_thread_id')
  end

  def validate_issue_thread_columns
    unless mtasks_issue_id.present? && hourglass_thread_id.present?
      errors.add(:base, 'issue_thread link requires mtasks_issue_id and hourglass_thread_id')
    end
    return if mtasks_project_id.blank? && hourglass_channel_id.blank?

    errors.add(:base, 'issue_thread link must not set mtasks_project_id or hourglass_channel_id')
  end
end
