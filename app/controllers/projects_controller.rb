class ProjectsController < ApplicationController
  include TeamScoped

  before_action :require_team!
  before_action :set_team
  before_action :set_project, only: %i[show edit update destroy purge_file]

  def index
    @index_sort = params[:sort].presence_in(%w[created name priority due_date velocity]) || 'created'
    @sort_dir = params[:dir].presence_in(%w[asc desc]) || 'asc'
    @hide_completed = params[:hide_completed] == '1'
    @projects = sorted_projects
  end

  def show
    @sort = params[:sort].presence_in(%w[newest status updated priority]) || 'newest'
    @issues = sorted_project_issues
    @lanes = current_team.lanes.order(:position)
    @team_members = current_team.users.order(:name)
    @labels = current_team.labels.order(:name)
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
      if turbo_stream_only_request?
        render_roadmap_card_stream
      elsif turbo_frame_request?
        render_sidebar_stream
      else
        redirect_to team_project_path(current_team, @project), notice: 'Project was successfully updated.'
      end
    else
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
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

  def turbo_stream_only_request?
    request.format.turbo_stream? && !request.accept.to_s.include?('text/html')
  end

  def render_roadmap_card_stream
    render turbo_stream: turbo_stream.replace(
      ActionView::RecordIdentifier.dom_id(@project, :roadmap_card),
      partial: 'roadmaps/card',
      locals: { project: @project }
    )
  end

  def render_sidebar_stream
    load_form_data
    render turbo_stream: turbo_stream.replace(
      'project_sidebar',
      partial: 'projects/sidebar',
      locals: { project: @project, team_members: @team_members, labels: @labels }
    )
  end

  def sorted_project_issues
    base = @project.issues.not_archived
                   .includes(:lane, :assignee, :labels, :blocking_dependencies, :blocked_dependencies)

    case @sort
    when 'status'   then base.joins(:lane).order('lanes.position ASC, issues.created_at DESC')
    when 'updated'  then base.order(updated_at: :desc)
    when 'priority' then base.order(priority: :asc, created_at: :desc)
    else base.order(created_at: :desc)
    end
  end

  def load_form_data
    @team_members = current_team.users.order(:name)
    @labels = current_team.labels.order(:name)
  end

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

  def project_params
    params.require(:project).permit(:name, :description, :priority, :status, :lead_id, :start_date,
                                    :due_date, :roadmap_commitment, files: [], label_ids: [])
  end
end
