# Team-member screen for issues that file themselves on a schedule. Member-level, like creating an
# issue: a recurring template only ever produces issues a member could have filed by hand.
class RecurringIssuesController < ApplicationController
  before_action :set_team
  before_action :authorize_team_member!
  before_action :set_recurring_issue, only: %i[edit update destroy]
  before_action :load_form_collections, only: %i[new create edit update]

  def index
    @recurring_issues = @team.recurring_issues.includes(:assignee, :project).order(:next_run_on, :title)
  end

  def new
    today = Time.current.in_time_zone(current_user.time_zone).to_date
    @recurring_issue = @team.recurring_issues.new(time_zone: current_user.time_zone,
                                                  weekday: today.wday, day_of_month: today.day)
  end

  def create
    @recurring_issue = @team.recurring_issues.new(time_zone: current_user.time_zone)
    @recurring_issue.assign_attributes(recurring_issue_params)
    @recurring_issue.creator = current_user
    @recurring_issue.schedule_from(start_date)

    if @recurring_issue.save
      redirect_to team_recurring_issues_path(@team), notice: 'Recurring issue created'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @recurring_issue.assign_attributes(recurring_issue_params)
    @recurring_issue.schedule_from(start_date)

    if @recurring_issue.save
      redirect_to team_recurring_issues_path(@team), notice: 'Recurring issue updated'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @recurring_issue.destroy
    redirect_to team_recurring_issues_path(@team), notice: 'Recurring issue deleted'
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
    authorize_team_access!(@team)
  end

  def authorize_team_member!
    return if performed? || @team.users.include?(current_user)

    redirect_to root_path, alert: 'Access denied'
  end

  def set_recurring_issue
    @recurring_issue = @team.recurring_issues.find(params[:id])
  end

  def load_form_collections
    @lanes = @team.lanes
    @team_members = @team.users.order(:name)
    @labels = @team.labels.order(:name)
    @projects = @team.projects.not_completed.order(:name)
  end

  def recurring_issue_params
    params.require(:recurring_issue)
          .permit(:title, :description, :priority, :assignee_id, :project_id, :lane_id,
                  :frequency, :interval, :weekday, :day_of_month, :time_zone, :active, label_ids: [])
          .tap { |permitted| permitted[:label_ids] = Array(permitted[:label_ids]).compact_blank.map(&:to_i) }
  end

  # The form's "starts on" date; an unparseable value leaves next_run_on blank so validation reports it.
  def start_date
    Date.iso8601(params.dig(:recurring_issue, :starts_on).to_s)
  rescue Date::Error
    nil
  end
end
