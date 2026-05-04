class IssuesController < ApplicationController
  include FormCollections
  include MentionNotifying

  before_action :require_team!
  before_action :set_issue, only: %i[show edit update destroy]
  before_action :authorize_issue_access!, only: %i[show]
  before_action :authorize_issue_modification!, only: %i[edit update destroy]
  before_action :load_display_options, only: %i[index]

  def index
    base_issues = current_team.issues.not_archived.includes(
      :lane, :project, :labels, :assignee,
      :blocking_dependencies, :blocked_dependencies, :comments
    )

    @display_service = build_display_service(base_issues)
    @grouped_issues = @display_service.grouped_issues
    @empty_groups = @display_service.empty_groups
    @lanes = current_team.lanes.order(:position)
    @labels = current_team.labels.includes(:issue_labels)
    @projects = current_team.projects.order(:name)
    @assignees = current_team.users.order(:name)
    @creators = @assignees
  end

  def show
    Current.user.notifications.unread.where(issue_id: @issue.id).update_all(read_at: Time.current)
    load_form_collections
  end

  def new
    @team = current_team
    @issue = current_team.issues.new
    @issue.lane_id = params[:lane_id] if params[:lane_id].present?
    @issue.project_id = params[:project_id] if params[:project_id].present?
    load_form_collections
  end

  def create
    @issue = current_team.issues.new(issue_params)
    @issue.creator = Current.user

    if @issue.save
      detect_issue_references
      notify_mentions_on(@issue, text: @issue.description)
      HourglassOutboundEmitterJob.dispatch_create(@issue, Current.user)
      redirect_after_create
    else
      load_form_collections
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_collections
  end

  def update
    load_form_collections
    @issue.assign_attributes(issue_params)
    @issue.apply_lane_timestamps!

    if @issue.save
      @issue.enqueue_velocity_recalculation!
      @latest_version = @issue.versions.last
      notify_issue_update
      notify_mentions_on(@issue, text: @issue.description, previous_text: @issue.description_previously_was)
      enqueue_after_update_job

      respond_to do |format|
        format.turbo_stream { render(:update) }
        format.html { redirect_to team_issue_path(@issue.team, @issue), notice: 'Issue was successfully updated.' }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    project_id = @issue.project_id
    @issue.destroy
    ProjectVelocityJob.perform_later(project_id) if project_id.present?
    redirect_to team_issues_path(@issue.team), notice: 'Issue was successfully deleted.'
  end

  def search
    issues = search_issues
    render json: issues.limit(20).map { |issue|
      { id: issue.id, identifier: issue.identifier, title: issue.title }
    }
  end

  private

  def search_issues
    query = params[:q].to_s.strip
    issues = current_team.issues.not_archived.includes(:lane)
    issues = issues.where.not(id: params[:exclude_id]) if params[:exclude_id].present?
    return issues unless query.present?

    issues.joins(:team).where(
      "title ILIKE :q OR CONCAT(teams.identifier, '-', issues.team_number::text) ILIKE :q",
      q: "%#{query}%"
    )
  end

  def set_issue
    @issue = Issue.includes(:team, :lane, :project, :labels, :assignee, :creator,
                            :sub_issues, :blocked_issues, :blocking_issues, comments: :user).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'Issue not found.'
  end

  def authorize_issue_access!
    return if current_team == @issue.team

    redirect_to root_path, alert: 'You do not have access to this issue.'
  end

  def authorize_issue_modification!
    # Allow any team member to update issues for inline editing
    return if current_team.users.include?(Current.user)

    # Only allow creator or admin for edit/destroy actions
    return if (Current.user.admin? || @issue.creator == Current.user) && action_name.in?(%w[edit destroy])

    redirect_to team_issue_path(@issue.team, @issue), alert: 'You do not have permission to modify this issue.'
  end

  def load_board_data
    load_display_options
    base_issues = current_team.issues.not_archived.includes(
      :lane, :project, :labels, :assignee, :creator, :blocking_dependencies, :blocked_dependencies, :comments
    )
    @display_service = build_display_service(base_issues)
    @grouped_issues = @display_service.grouped_issues
    @empty_groups = @display_service.empty_groups
  end

  def build_display_service(base_issues)
    IssueDisplayService.new(base_issues, @display_options.merge(search_query: params[:q]), current_team)
  end

  def redirect_after_create
    if params[:create_more] == '1'
      redirect_to new_team_issue_path(@issue.team), notice: 'Issue was successfully created. Create another?'
    else
      redirect_to team_issues_path(@issue.team), notice: 'Issue was successfully created.'
    end
  end

  def enqueue_after_update_job
    IssueAfterUpdateJob.perform_later(
      issue_id: @issue.id, user_id: Current.user.id,
      description_changed: @issue.saved_change_to_description?, version_id: @latest_version&.id
    )
  end

  def notify_issue_update
    version = @issue.versions.last
    return unless version&.event == 'update'

    NotificationJob.perform_later(
      issue_id: @issue.id, actor_id: Current.user.id,
      action: NotificationService.action_for_version(version), version_id: version.id
    )
  end

  def detect_issue_references
    IssueReferenceService.call(source_issue: @issue, text: @issue.description,
                               source_type: 'description', user: Current.user)
  end

  def issue_params
    params.require(:issue).permit(
      :title, :description, :lane_id, :priority, :estimate, :due_date, :assignee_id, :project_id,
      :parent_issue_id, label_ids: [], files: []
    )
  end

  def load_display_options
    @display_options = DisplayOptionsService.call(params, Current.user, current_team)
  end
end
