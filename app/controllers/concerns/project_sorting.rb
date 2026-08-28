# The ordering rules behind the projects index and the project show page's issue list.
# Extracted from ProjectsController so it stays under Metrics/ClassLength; no behavior change.
module ProjectSorting
  extend ActiveSupport::Concern

  private

  def sorted_projects
    scope = current_team.projects.includes(:lead)
    scope = scope.where.not(status: 'completed') if @hide_completed
    direction = @sort_dir.to_sym
    case @index_sort
    when 'name'     then scope.order(name: direction)
    when 'priority' then scope.order(priority: direction, created_at: :asc)
    when 'due_date' then scope.order(due_date_order(direction))
    when 'velocity' then scope.order(velocity_score: direction, created_at: direction)
    else scope.order(created_at: direction)
    end
  end

  def due_date_order(direction)
    Arel.sql("due_date IS NULL, due_date #{direction == :asc ? 'ASC' : 'DESC'}")
  end

  def sorted_project_issues
    base = @project.issues.not_archived
                   .includes(:lane, :assignee, :labels, :blocking_dependencies, :blocked_dependencies)
    base = base.where(completed_at: nil, canceled_at: nil) if @issue_filter == 'active'

    case @sort
    when 'id'       then base.order(team_number: :asc)
    when 'status'   then base.joins(:lane).order('lanes.position ASC, issues.created_at DESC')
    when 'updated'  then base.order(updated_at: :desc)
    when 'priority' then base.order(priority: :asc, created_at: :desc)
    else base.order(created_at: :desc)
    end
  end
end
