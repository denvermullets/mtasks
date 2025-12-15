class IssuesController < ApplicationController
  before_action :require_team!
  before_action :set_issue, only: %i[show edit update destroy]
  before_action :authorize_issue_access!, only: %i[show]
  before_action :authorize_issue_modification!, only: %i[edit update destroy]

  def index
    @view_mode = params[:view] || 'lanes'
    @issues = current_team.issues.not_archived.includes(:lane, :project, :milestone, :labels, :assignee, :creator)
    @lanes = current_team.lanes.includes(:issues)

    case @view_mode
    when 'milestone'
      @milestones = current_team.milestones.includes(projects: :issues)
      @ungrouped_issues = @issues.where(milestone_id: nil, project_id: nil)
    end
  end

  def show
    load_form_collections
  end

  def new
    @issue = current_team.issues.new
    load_form_collections
  end

  def create
    @issue = current_team.issues.new(issue_params)
    @issue.creator = Current.user

    if @issue.save
      redirect_to team_issue_path(@issue.team, @issue), notice: 'Issue was successfully created.'
    else
      load_form_collections
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_collections
  end

  def update
    if @issue.update(issue_params)
      redirect_to team_issue_path(@issue.team, @issue), notice: 'Issue was successfully updated.'
    else
      load_form_collections
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @issue.destroy
    redirect_to team_issues_path(@issue.team), notice: 'Issue was successfully deleted.'
  end

  private

  def set_issue
    @issue = Issue.includes(:team, :lane, :project, :milestone, :labels, :assignee, :creator,
                            :sub_issues).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'Issue not found.'
  end

  def authorize_issue_access!
    return if current_team == @issue.team

    redirect_to root_path, alert: 'You do not have access to this issue.'
  end

  def authorize_issue_modification!
    return if Current.user.admin? || @issue.creator == Current.user

    redirect_to team_issue_path(@issue.team, @issue), alert: 'You do not have permission to modify this issue.'
  end

  def load_form_collections
    @lanes = current_team.lanes
    @team_members = current_team.users
    @labels = current_team.labels
    @projects = current_team.projects
    @milestones = current_team.milestones
  end

  def issue_params
    params.require(:issue).permit(
      :title,
      :description,
      :lane_id,
      :priority,
      :estimate,
      :due_date,
      :assignee_id,
      :project_id,
      :milestone_id,
      :parent_issue_id,
      label_ids: []
    )
  end
end
