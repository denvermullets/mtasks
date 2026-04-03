class ProjectsController < ApplicationController
  include TeamScoped

  before_action :require_team!
  before_action :set_team
  before_action :set_project, only: %i[show edit update destroy purge_file]

  def index
    @projects = current_team.projects.includes(:milestone).order(created_at: :desc)
  end

  def show
    @issues = @project.issues.not_archived.includes(:lane, :assignee, :labels).order(created_at: :desc)
    @lanes = current_team.lanes.order(:position)
    @team_members = current_team.users.order(:name)
    @labels = current_team.labels.order(:name)
    @milestones = current_team.milestones.order(:name)
  end

  def new
    @project = current_team.projects.new
    load_form_data
  end

  def create
    @project = current_team.projects.new(project_params)

    if @project.save
      redirect_to team_project_path(current_team, @project), notice: 'Project was successfully created.'
    else
      load_form_data
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_data
  end

  def update
    if @project.update(project_params)
      if turbo_frame_request?
        render_sidebar_stream
      else
        redirect_to team_project_path(current_team, @project), notice: 'Project was successfully updated.'
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to team_projects_path(current_team), notice: 'Project was successfully deleted.'
  end

  def purge_file
    attachment = @project.files.find(params[:file_id])
    attachment.purge
    redirect_to edit_team_project_path(current_team, @project), notice: 'File removed.'
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

  def render_sidebar_stream
    load_form_data
    render turbo_stream: turbo_stream.replace(
      'project_sidebar',
      partial: 'projects/sidebar',
      locals: { project: @project, team_members: @team_members, labels: @labels, milestones: @milestones }
    )
  end

  def load_form_data
    @team_members = current_team.users.order(:name)
    @labels = current_team.labels.order(:name)
    @milestones = current_team.milestones.order(:name)
  end

  def project_params
    params.require(:project).permit(:name, :description, :milestone_id, :priority, :status, :lead_id, :start_date,
                                    :due_date, files: [], label_ids: [])
  end
end
