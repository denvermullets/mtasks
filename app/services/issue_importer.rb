require 'csv'

class IssueImporter
  attr_reader :team, :errors, :imported_count

  def initialize(team)
    @team = team
    @errors = []
    @imported_count = 0
    @old_id_to_new_issue = {}
  end

  def import(csv_file_path_or_string)
    csv_data = if csv_file_path_or_string.is_a?(String) && File.exist?(csv_file_path_or_string)
                 File.read(csv_file_path_or_string)
               else
                 csv_file_path_or_string
               end

    CSV.parse(csv_data, headers: true) do |row|
      import_issue(row)
    end

    # Second pass to set parent issues
    update_parent_issues

    { success: @errors.empty?, imported: @imported_count, errors: @errors }
  end

  private

  def import_issue(row)
    old_id = row['ID']
    title = row['Title']
    description = row['Description']
    estimate = row['Estimate'].to_i if row['Estimate'].present?
    priority = map_priority(row['Priority'])
    due_date = parse_date(row['Due Date'])

    # Find or create lane by status name
    lane = find_or_create_lane(row['Status'])

    # Find or create project and milestone
    project = find_or_create_project(row['Project'], row['Project Milestone'])
    milestone = project&.milestone || find_or_create_milestone(row['Project Milestone'])

    # Find or create users
    creator = find_user_by_name(row['Creator'])
    assignee = find_user_by_name(row['Assignee'])

    issue = Issue.new(
      title: title,
      description: description,
      team: @team,
      lane: lane,
      estimate: estimate,
      priority: priority,
      due_date: due_date,
      project: project,
      milestone: milestone,
      creator: creator,
      assignee: assignee,
      created_at: parse_date(row['Created']),
      updated_at: parse_date(row['Updated']),
      started_at: parse_date(row['Started']),
      completed_at: parse_date(row['Completed']),
      canceled_at: parse_date(row['Canceled']),
      archived_at: parse_date(row['Archived'])
    )

    if issue.save
      @old_id_to_new_issue[old_id] = issue

      # Handle labels
      if row['Labels'].present?
        label_names = row['Labels'].split(',').map(&:strip)
        label_names.each do |label_name|
          label = find_or_create_label(label_name)
          issue.labels << label unless issue.labels.include?(label)
        end
      end

      # Store parent issue ID for second pass
      issue.instance_variable_set(:@parent_issue_old_id, row['Parent issue']) if row['Parent issue'].present?

      @imported_count += 1
    else
      @errors << "Row #{old_id}: #{issue.errors.full_messages.join(', ')}"
    end
  rescue StandardError => e
    @errors << "Row #{old_id}: #{e.message}"
  end

  def update_parent_issues
    @old_id_to_new_issue.each_value do |issue|
      parent_old_id = issue.instance_variable_get(:@parent_issue_old_id)
      if parent_old_id && (parent_issue = @old_id_to_new_issue[parent_old_id])
        issue.update(parent_issue: parent_issue)
      end
    end
  end

  def find_or_create_lane(status_name)
    return @team.lanes.first unless status_name.present?

    @team.lanes.find_or_create_by!(name: status_name) do |lane|
      lane.position = @team.lanes.maximum(:position).to_i + 1
      lane.color = '#6b7280'
    end
  end

  def find_or_create_project(project_name, milestone_name)
    return nil unless project_name.present?

    milestone = find_or_create_milestone(milestone_name) if milestone_name.present?

    @team.projects.find_or_create_by!(name: project_name) do |project|
      project.milestone = milestone
    end
  end

  def find_or_create_milestone(milestone_name)
    return nil unless milestone_name.present?

    @team.milestones.find_or_create_by!(name: milestone_name)
  end

  def find_or_create_label(label_name)
    @team.labels.find_or_create_by!(name: label_name) do |label|
      label.color = random_color
    end
  end

  def find_user_by_name(name)
    return nil unless name.present?

    # Try to find user by name in the team
    @team.users.find_by('name ILIKE ?', name)
  end

  def map_priority(priority_str)
    return :no_priority unless priority_str.present?

    case priority_str.downcase
    when 'urgent' then :urgent
    when 'high' then :high
    when 'medium' then :medium
    when 'low' then :low
    else :no_priority
    end
  end

  def parse_date(date_str)
    return nil unless date_str.present?

    Date.parse(date_str)
  rescue StandardError
    nil
  end

  def random_color
    colors = ['#ef4444', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6', '#ec4899']
    colors.sample
  end
end
