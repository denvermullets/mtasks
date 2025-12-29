class IssuesController < ApplicationController
  include FormCollections

  before_action :require_team!
  before_action :set_issue, only: %i[show edit update destroy]
  before_action :authorize_issue_access!, only: %i[show]
  before_action :authorize_issue_modification!, only: %i[edit update destroy]
  before_action :load_display_options, only: %i[index]

  def index
    base_issues = current_team.issues.not_archived.includes(
      :lane, :project, :milestone, :labels, :assignee, :creator
    )

    @display_service = IssueDisplayService.new(base_issues, @display_options, current_team)
    @grouped_issues = @display_service.grouped_issues
    @lanes = current_team.lanes.order(:position)
    @labels = current_team.labels.includes(:issue_labels)
  end

  def show
    load_form_collections
  end

  def new
    @team = current_team
    @issue = current_team.issues.new
    load_form_collections
  end

  def create
    @issue = current_team.issues.new(issue_params)
    @issue.creator = Current.user

    if @issue.save
      if params[:create_more] == '1'
        redirect_to new_team_issue_path(@issue.team), notice: 'Issue was successfully created. Create another?'
      else
        redirect_to team_issues_path(@issue.team), notice: 'Issue was successfully created.'
      end
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
    if @issue.update(issue_params)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: issue_update_streams }
        format.html { redirect_to team_issue_path(@issue.team, @issue), notice: 'Issue was successfully updated.' }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @issue.destroy
    redirect_to team_issues_path(@issue.team), notice: 'Issue was successfully deleted.'
  end

  private

  def issue_update_streams
    IssueTurboStreamService.new(
      @issue, Current.user, current_team, view_context,
      { lanes: @lanes, team_members: @team_members, projects: @projects, labels: @labels, milestones: @milestones }
    ).update_streams
  end

  def set_issue
    @issue = Issue.includes(:team, :lane, :project, :milestone, :labels, :assignee, :creator,
                            :sub_issues, comments: :user).find(params[:id])
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

  def load_display_options
    @display_options = DisplayOptionsService.call(params, Current.user, current_team)
  end
end
