# Everything dashboards/show needs to render: the resolved issue groups plus the pick lists
# for the group modal. Shared by DashboardsController and DashboardGroupsController, which
# both re-render the page on a failed save.
module DashboardPage
  extend ActiveSupport::Concern

  # Query params that identify the view the user was on; every redirect and form URL keeps them.
  RETURN_PARAMS = %w[filter mine].freeze

  included do
    helper_method :dashboard_return_params
  end

  private

  def dashboard_return_params
    request.query_parameters.slice(*RETURN_PARAMS)
  end

  def load_dashboard_page
    @result = DashboardIssuesQuery.call(
      user: current_user, dashboard: @dashboard,
      filter: params[:filter], mine: params[:mine]
    )
    @mine = ActiveModel::Type::Boolean.new.cast(params[:mine]) || false
    @modal_teams = modal_teams
    @modal_projects = modal_projects(@modal_teams.map(&:id))
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
