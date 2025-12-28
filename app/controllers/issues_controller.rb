# rubocop:disable Metrics/ClassLength
class IssuesController < ApplicationController
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
        format.turbo_stream do
          service = IssueTurboStreamService.new(
            @issue,
            Current.user,
            current_team,
            { lanes: @lanes, team_members: @team_members, projects: @projects }
          )
          render turbo_stream: service.update_streams(self)
        end
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

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def load_display_options
    saved_prefs = UserPreference.for_user_and_team(Current.user, current_team)

    @display_options = {
      view_mode: params[:view_mode] || saved_prefs.view_mode,
      group_by: params[:group_by] || saved_prefs.group_by,
      sub_group_by: params[:sub_group_by] || saved_prefs.sub_group_by || 'none',
      order_by: params[:order_by] || saved_prefs.order_by,
      show_sub_issues: param_to_bool(params[:show_sub_issues], saved_prefs.show_sub_issues),
      show_empty_groups: param_to_bool(params[:show_empty_groups], saved_prefs.show_empty_groups),
      show_empty_rows: param_to_bool(params[:show_empty_rows], saved_prefs.show_empty_rows),
      completed_filter: params[:completed_filter] || saved_prefs.completed_filter,
      visible_properties: params[:visible_properties]&.split(',') || saved_prefs.visible_properties_array,
      milestone_id: params[:milestone_id]
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def param_to_bool(param, default)
    return default if param.nil?

    %w[true 1].include?(param.to_s)
  end
end
# rubocop:enable Metrics/ClassLength
