class ProjectLabelsController < ApplicationController
  include TeamScoped

  before_action :set_project

  def create
    label = current_team.labels.find(params[:label_id])
    project_label = @project.project_labels.build(label: label)

    if project_label.save
      @project.reload
      load_sidebar_data
    else
      render turbo_stream: turbo_stream.append('errors', 'Error adding label'), status: :unprocessable_entity
    end
  end

  def destroy
    project_label = @project.project_labels.find_by(label_id: params[:id])

    if project_label
      project_label.destroy
      @project.reload
      load_sidebar_data
    else
      render turbo_stream: turbo_stream.append('errors', 'Label not found'), status: :not_found
    end
  end

  private

  def set_project
    @project = current_team.projects.find(params[:project_id])
  end

  def load_sidebar_data
    @team_members = current_team.users.order(:name)
    @labels = current_team.labels.order(:name)
    @milestones = current_team.milestones.order(:name)
  end
end
