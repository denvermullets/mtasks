class ProjectsController < ApplicationController
  include TeamScoped
  include ProjectSorting

  before_action :require_team!
  before_action :set_team
  before_action :set_project, only: %i[show edit update destroy purge_file overview discussion activity card]

  def index
    @index_sort = params[:sort].presence_in(%w[created name priority due_date velocity]) || 'created'
    @sort_dir = params[:dir].presence_in(%w[asc desc]) || 'asc'
    @hide_completed = params[:hide_completed] != '0'
    @projects = sorted_projects
  end

  def show
    @active_tab = :issues
    load_show_data!
  end

  def overview
    @active_tab = :overview
    load_show_data!
    render :show
  end

  def discussion
    @active_tab = :discussion
    @channel_link = @project.hourglass_channel_link
    @thread_id = params[:thread].presence
    load_show_data!
    render :show
  end

  def activity
    @active_tab = :activity
    load_show_data!
    render :show
  end

  def new
    @project = current_team.projects.new
    load_form_data
  end

  def create
    @project = current_team.projects.new(project_params)

    if @project.save
      track_feature('project-management', 'create', **project_shape)
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
      track_project_updated
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
    track_feature('project-management', 'delete') if @project.destroyed?
    redirect_to team_projects_path(current_team), notice: 'Project was successfully deleted.'
  end

  def purge_file
    attachment = @project.files.find(params[:file_id])
    attachment.purge
    # issue-attachment is the one permanent slug for files anywhere in the app; `entity` is what
    # separates a project file from an issue or comment file (taxonomy §5.2, amended by VEK-584).
    track_feature('issue-attachment', 'remove', entity: 'project', count: 1)
    redirect_to edit_team_project_path(current_team, @project), notice: 'File removed.'
  end

  def card
    render partial: 'projects/hover_card', locals: { project: @project }, layout: false
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

  def project_shape
    { priority: @project.priority, has_due_date: @project.due_date.present? }
  end

  # roadmap_add_controller.js and commitment_picker_controller.js both PATCH roadmap_commitment
  # on its own. Only nil -> present is the `create` the catalog names; a lane-to-lane reshuffle
  # or a removal falls through to project-management/update, which is what it genuinely is.
  def track_project_updated
    return track_feature('roadmap', 'create') if roadmap_add?

    track_feature('project-management', 'update', **project_shape)
  end

  def roadmap_add?
    before, after = @project.saved_change_to_roadmap_commitment
    return false unless before.nil? && after.present?

    (@project.saved_changes.keys - %w[roadmap_commitment updated_at]).empty?
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

  def load_show_data!
    @sort = params[:sort].presence_in(%w[newest id status updated priority]) || 'id'
    @issue_filter = params[:filter].presence_in(%w[all active]) || 'active'
    @issues = sorted_project_issues
    @lanes = current_team.lanes.order(:position)
    @team_members = current_team.users.order(:name)
    @labels = current_team.labels.order(:name)
    @thread_counts = HourglassThreadCountService.call(issues: @issues, user: Current.user)
  end

  def load_form_data
    @team_members = current_team.users.order(:name)
    @labels = current_team.labels.order(:name)
  end

  def project_params
    permitted = params.require(:project).permit(:name, :description, :priority, :status, :lead_id, :start_date,
                                                :due_date, :roadmap_commitment, files: [], label_ids: [])
    permitted[:roadmap_commitment] = nil if permitted[:status] == 'completed'
    permitted
  end
end
