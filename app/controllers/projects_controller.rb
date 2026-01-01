class ProjectsController < ApplicationController
  include TeamScoped

  before_action :require_team!
  before_action :set_team
  before_action :set_project, only: %i[show edit update destroy]

  def index
    @projects = current_team.projects.includes(:milestone).order(created_at: :desc)
  end

  def show; end

  def new
    @project = current_team.projects.new
  end

  def create
    @project = current_team.projects.new(project_params)

    if @project.save
      redirect_to team_projects_path(current_team), notice: 'Project was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @project.update(project_params)
      redirect_to team_project_path(current_team, @project), notice: 'Project was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to team_projects_path(current_team), notice: 'Project was successfully deleted.'
  end

  private

  def set_team
    @team = current_team
  end

  def set_project
    @project = current_team.projects.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to team_projects_path(current_team), alert: 'Project not found.'
  end

  def project_params
    params.require(:project).permit(:name, :description, :milestone_id)
  end
end
