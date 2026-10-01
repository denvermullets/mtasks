# Groups belong to a user-owned dashboard, so every lookup goes through current_user.dashboards
# and a foreign dashboard or group id is simply not found. Source ids from the client are
# intersected with the teams/projects/labels the user can actually see; the rest are dropped silently.
class DashboardGroupsController < ApplicationController
  include DashboardPage

  SOURCE_ID_KEYS = %i[team_ids project_ids label_ids all_team_ids all_project_ids].freeze

  before_action :set_dashboard
  before_action :set_group, only: %i[update destroy move]

  def create
    # Not @dashboard.groups.build: has_many inversing would put the unsaved record in the
    # association target, and the page (and DashboardIssuesQuery) would render it on a 422.
    @group = DashboardGroup.new(group_attributes.merge(dashboard_id: @dashboard.id))
    @group.position = @dashboard.groups.maximum(:position).to_i + 1
    save_and_respond('Group added')
  end

  def update
    @group.assign_attributes(group_attributes)
    save_and_respond('Group updated')
  end

  def destroy
    @group.destroy
    redirect_to return_path, notice: 'Group deleted'
  end

  def move
    return head :bad_request unless DashboardGroup::DIRECTIONS.include?(params[:direction])

    @group.move!(params[:direction])
    redirect_to return_path
  end

  # Drag-and-drop on the dashboard. The page already shows the new order, so there's nothing to render.
  def reorder
    @dashboard.reorder_groups!(params[:ids])
    head :no_content
  end

  private

  def set_dashboard
    @dashboard = current_user.dashboards.find(params[:dashboard_id])
  end

  def set_group
    @group = @dashboard.groups.find(params[:id])
  end

  def return_path
    dashboard_path(@dashboard, dashboard_return_params)
  end

  def save_and_respond(notice)
    sources = permitted_sources
    saved = DashboardGroup.transaction { @group.save && @group.replace_sources!(**sources) }
    return redirect_to(return_path, notice: notice) if saved

    # Re-render the page with the modal open. The submitted (sanitized) ids are handed to the
    # view so the user's unsaved checkbox changes survive the round trip.
    @form_group = @group
    @form_sources = sources
    load_dashboard_page
    render 'dashboards/show', status: :unprocessable_entity
  end

  def group_params
    params.require(:dashboard_group).permit(:name, :description, :color, **SOURCE_ID_KEYS.index_with([]))
  end

  # The model exposes the id lists as readers only; sources are synced separately.
  def group_attributes
    group_params.except(*SOURCE_ID_KEYS)
  end

  # Keyword args for DashboardGroup#replace_sources!. `all_*` ids only count when they're also sources.
  def permitted_sources
    team_ids = permitted_team_ids
    project_ids = permitted_project_ids
    label_ids = permitted_label_ids

    {
      team_ids: team_ids, project_ids: project_ids, label_ids: label_ids,
      all_team_ids: submitted_ids(:all_team_ids) & team_ids,
      all_project_ids: submitted_ids(:all_project_ids) & project_ids
    }
  end

  # collection_check_boxes posts a blank entry so the key is always present; drop it.
  def submitted_ids(key)
    Array(group_params[key]).map(&:to_i).reject(&:zero?)
  end

  def allowed_team_ids
    @allowed_team_ids ||= current_user.teams.not_archived.pluck(:id)
  end

  def permitted_team_ids
    submitted_ids(:team_ids) & allowed_team_ids
  end

  def permitted_project_ids
    ids = submitted_ids(:project_ids)
    return [] if ids.empty?

    Project.where(id: ids, team_id: allowed_team_ids).pluck(:id)
  end

  def permitted_label_ids
    ids = submitted_ids(:label_ids)
    return [] if ids.empty?

    Label.where(id: ids, team_id: allowed_team_ids).pluck(:id)
  end
end
