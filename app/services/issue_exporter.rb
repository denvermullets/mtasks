require 'csv'

class IssueExporter
  HEADERS = [
    'ID', 'Team', 'Title', 'Description', 'Status', 'Estimate', 'Priority',
    'Project ID', 'Project', 'Creator', 'Assignee', 'Labels',
    'Created', 'Updated', 'Started', 'Completed', 'Canceled', 'Archived',
    'Due Date', 'Parent issue', 'Project Milestone ID', 'Project Milestone'
  ].freeze

  PRIORITY_LABELS = {
    'urgent' => 'Urgent',
    'high' => 'High',
    'medium' => 'Medium',
    'low' => 'Low',
    'no_priority' => 'No priority'
  }.freeze

  def initialize(team)
    @team = team
  end

  def to_csv
    CSV.generate do |csv|
      csv << HEADERS
      issues.each { |issue| csv << row_for(issue) }
    end
  end

  def issue_count
    issues.size
  end

  private

  def issues
    @issues ||= @team.issues.includes(:lane, :project, :milestone, :assignee, :creator, :labels,
                                      :parent_issue).order(:team_number)
  end

  def row_for(issue)
    core_fields(issue) + association_fields(issue) + timestamp_fields(issue) + trailing_fields(issue)
  end

  def core_fields(issue)
    [
      issue.identifier,
      @team.name,
      issue.title,
      issue.description,
      issue.lane&.name,
      issue.estimate,
      PRIORITY_LABELS[issue.priority]
    ]
  end

  def association_fields(issue)
    [
      issue.project_id,
      issue.project&.name,
      issue.creator&.name,
      issue.assignee&.name,
      issue.labels.map(&:name).join(', ')
    ]
  end

  def timestamp_fields(issue)
    [
      issue.created_at&.iso8601,
      issue.updated_at&.iso8601,
      issue.started_at&.iso8601,
      issue.completed_at&.iso8601,
      issue.canceled_at&.iso8601,
      issue.archived_at&.iso8601
    ]
  end

  def trailing_fields(issue)
    [
      issue.due_date&.iso8601,
      issue.parent_issue&.identifier,
      issue.milestone_id,
      issue.milestone&.name
    ]
  end
end
