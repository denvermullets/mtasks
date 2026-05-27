class ProjectVelocityJob < ApplicationJob
  queue_as :default

  def perform(project_id)
    project = Project.find_by(id: project_id)
    return unless project

    project.recalculate_velocity!
    broadcast_project_updates(project)
  end

  private

  def broadcast_project_updates(project)
    stream = "project_#{project.id}"

    Turbo::StreamsChannel.broadcast_replace_to(
      stream, target: "project_progress_chart_#{project.id}",
              partial: 'projects/progress_chart', locals: { project: project }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream, target: "project_issues_list_#{project.id}",
              partial: 'projects/issues_list', locals: issues_list_locals(project)
    )
  end

  def issues_list_locals(project)
    {
      project: project,
      issues: project.issues.not_archived
                     .includes(:lane, :assignee, :labels, :blocking_dependencies, :blocked_dependencies)
                     .order(created_at: :desc),
      team: project.team,
      lanes: project.team.lanes.order(:position),
      labels: project.team.labels.order(:name)
    }
  end
end
