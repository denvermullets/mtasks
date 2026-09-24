# Everything dashboards/show needs to render: the resolved issue groups plus the pick lists
# for the group modal. Shared by DashboardsController and DashboardGroupsController, which
# both re-render the page on a failed save.
module DashboardPage
  extend ActiveSupport::Concern

  # Query params that identify the view the user was on; every redirect and form URL keeps them.
  # `team` (not `team_id`): TeamScoped#set_current_team reads params[:team_id] into the session.
  RETURN_PARAMS = %w[filter mine q team].freeze

  included do
    helper_method :dashboard_return_params
  end

  private

  # compact_blank: the header search form submits every field, so `q=` / `team=` show up empty.
  def dashboard_return_params
    request.query_parameters.slice(*RETURN_PARAMS).compact_blank
  end

  def load_dashboard_page
    @result = DashboardIssuesQuery.call(user: current_user, dashboard: @dashboard, **query_options)
    @mine = ActiveModel::Type::Boolean.new.cast(params[:mine]) || false
    @modal_teams = modal_teams
    @modal_projects = modal_projects(@modal_teams.map(&:id))
    # Teams offered in the header picker: only those behind this dashboard's sources, sidebar order.
    @filter_teams = @modal_teams.select { |team| @result.team_ids.include?(team.id) }
  end

  # URL param -> query option. `team` on the wire, `team_id` in the service (see RETURN_PARAMS).
  def query_options
    { filter: params[:filter], mine: params[:mine], search: params[:q], team_id: params[:team] }
  end

  # Same order as the sidebar: owned teams first, each half in the user's saved order.
  def modal_teams
    owned, joined = user_teams.partition { |team| team_owner?(team) }
    current_user.order_teams(owned, :owned) + current_user.order_teams(joined, :joined)
  end

  # Open projects on the user's teams, plus completed ones a group on this dashboard still
  # points at (so they stay visible and can be unchecked). Returns { team_id => [projects] }.
  def modal_projects(team_ids)
    kept = DashboardGroupSource.where(dashboard_group_id: @dashboard.groups.select(:id), source_type: 'Project')
                               .select(:source_id)

    Project.where(team_id: team_ids)
           .merge(Project.not_completed.or(Project.where(id: kept)))
           .order(:name)
           .group_by(&:team_id)
  end
end
