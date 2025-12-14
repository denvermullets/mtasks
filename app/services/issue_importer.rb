require 'csv'

# rubocop:disable Metrics/ClassLength
class IssueImporter
  attr_reader :workspace, :user, :errors, :imported_count

  def initialize(workspace, user)
    @workspace = workspace
    @user = user
    @errors = []
    @imported_count = 0
    @old_id_to_new_issue = {}
    @team_cache = {}
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
    issue = build_issue_from_row(row)

    if issue.save
      handle_successful_import(issue, old_id, row)
    else
      @errors << "Row #{old_id}: #{issue.errors.full_messages.join(', ')}"
    end
  rescue StandardError => e
    @errors << "Row #{old_id}: #{e.message}"
  end

  def build_issue_from_row(row)
    Issue.new(issue_attributes(row))
  end

  def issue_attributes(row)
    team = find_or_create_team(row['Team'])
    {
      title: row['Title'],
      description: row['Description'],
      team: team,
      lane: find_or_create_lane(row['Status'], team),
      estimate: parse_estimate(row['Estimate']),
      priority: map_priority(row['Priority']),
      due_date: parse_date(row['Due Date'])
    }.merge(issue_associations(row, team))
      .merge(issue_timestamps(row))
  end

  def issue_associations(row, team)
    {
      project: find_or_create_project(row['Project'], row['Project Milestone'], team),
      milestone: find_milestone_for_row(row, team),
      creator: find_user_by_name(row['Creator'], team),
      assignee: find_user_by_name(row['Assignee'], team)
    }
  end

  def issue_timestamps(row)
    {
      created_at: parse_date(row['Created']),
      updated_at: parse_date(row['Updated']),
      started_at: parse_date(row['Started']),
      completed_at: parse_date(row['Completed']),
      canceled_at: parse_date(row['Canceled']),
      archived_at: parse_date(row['Archived'])
    }
  end

  def handle_successful_import(issue, old_id, row)
    @old_id_to_new_issue[old_id] = issue
    attach_labels(issue, row['Labels'], issue.team)
    store_parent_issue_id(issue, row['Parent issue'])
    @imported_count += 1
  end

  def find_milestone_for_row(row, team)
    project = find_or_create_project(row['Project'], row['Project Milestone'], team)
    project&.milestone || find_or_create_milestone(row['Project Milestone'], team)
  end

  def attach_labels(issue, labels_string, team)
    return unless labels_string.present?

    label_names = labels_string.split(',').map(&:strip)
    label_names.each do |label_name|
      label = find_or_create_label(label_name, team)
      issue.labels << label unless issue.labels.include?(label)
    end
  end

  def store_parent_issue_id(issue, parent_id)
    return unless parent_id.present?

    issue.instance_variable_set(:@parent_issue_old_id, parent_id)
  end

  def parse_estimate(estimate_str)
    estimate_str.to_i if estimate_str.present?
  end

  def update_parent_issues
    @old_id_to_new_issue.each_value do |issue|
      parent_old_id = issue.instance_variable_get(:@parent_issue_old_id)
      if parent_old_id && (parent_issue = @old_id_to_new_issue[parent_old_id])
        issue.update(parent_issue: parent_issue)
      end
    end
  end

  def find_or_create_team(team_name)
    # If no team name provided, use first team in workspace or create a default team
    team_name = team_name.presence || 'Default'

    # Return cached team if we've already found/created it
    return @team_cache[team_name] if @team_cache[team_name]

    # Generate identifier: extract only letters, take first 3, uppercase
    letters_only = team_name.gsub(/[^A-Za-z]/, '')
    identifier = if letters_only.length >= 3
                   letters_only[0..2].upcase
                 else
                   # Pad with X if not enough letters
                   letters_only.upcase.ljust(3, 'X')
                 end

    # Find or create the team
    team = @workspace.teams.find_or_create_by!(identifier: identifier) do |t|
      t.name = team_name
    end

    # Ensure the user has access to this team
    team.team_memberships.find_or_create_by!(user: @user)

    @team_cache[team_name] = team
  end

  def find_or_create_lane(status_name, team)
    return team.lanes.first unless status_name.present?

    team.lanes.find_or_create_by!(name: status_name) do |lane|
      lane.position = team.lanes.maximum(:position).to_i + 1
      lane.color = '#6b7280'
    end
  end

  def find_or_create_project(project_name, milestone_name, team)
    return nil unless project_name.present?

    milestone = find_or_create_milestone(milestone_name, team) if milestone_name.present?

    team.projects.find_or_create_by!(name: project_name) do |project|
      project.milestone = milestone
    end
  end

  def find_or_create_milestone(milestone_name, team)
    return nil unless milestone_name.present?

    team.milestones.find_or_create_by!(name: milestone_name)
  end

  def find_or_create_label(label_name, team)
    team.labels.find_or_create_by!(name: label_name) do |label|
      label.color = random_color
    end
  end

  def find_user_by_name(name, team)
    return nil unless name.present?

    # Try to find user by name in the team
    team.users.find_by('name ILIKE ?', name)
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
# rubocop:enable Metrics/ClassLength
