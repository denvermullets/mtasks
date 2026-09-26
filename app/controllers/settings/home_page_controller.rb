# Per-user landing page: the last-used team's issues board (default), a specific team's issues board,
# one of the user's saved views, or one of their dashboards. Stored in users.settings as home_team_id /
# home_view_id / home_dashboard_id (at most one is set); the form posts a single `home` value like
# "team:3", "view:7" or "dashboard:5", blank for default.
class Settings::HomePageController < ApplicationController
  HOME_KEYS = { 'team' => 'home_team_id', 'view' => 'home_view_id', 'dashboard' => 'home_dashboard_id' }.freeze

  def update
    kind, id = params[:home].to_s.split(':', 2)
    key = HOME_KEYS[kind]

    if params[:home].present? && !(key && valid_target?(kind, id))
      redirect_to settings_path(section: 'home_page'), alert: 'Unknown home page.', status: :see_other and return
    end

    save_home(key, id)
    redirect_to settings_path(section: 'home_page'), notice: 'Home page saved', status: :see_other
  end

  private

  def save_home(key, id)
    settings = (current_user.settings || {}).except(*HOME_KEYS.values)
    settings[key] = id.to_i if key
    current_user.update!(settings: settings)
  end

  def valid_target?(kind, id)
    scope = case kind
            when 'team' then user_teams
            when 'view' then current_user.saved_views.where(team_id: user_teams.select(:id))
            else current_user.dashboards
            end
    scope.exists?(id: id)
  end
end
