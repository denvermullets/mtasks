# Per-user landing page: the last-used team's issues board (default), a specific team's issues board,
# or one of the user's dashboards. Stored in users.settings as home_team_id / home_dashboard_id (at most
# one is set); the form posts a single `home` value like "team:3" or "dashboard:5", blank for default.
class Settings::HomePageController < ApplicationController
  def update
    kind, id = params[:home].to_s.split(':', 2)
    key = { 'team' => 'home_team_id', 'dashboard' => 'home_dashboard_id' }[kind]

    if params[:home].present? && !(key && valid_target?(kind, id))
      redirect_to settings_path(section: 'home_page'), alert: 'Unknown home page.', status: :see_other and return
    end

    save_home(key, id)
    redirect_to settings_path(section: 'home_page'), notice: 'Home page saved', status: :see_other
  end

  private

  def save_home(key, id)
    settings = (current_user.settings || {}).except('home_team_id', 'home_dashboard_id')
    settings[key] = id.to_i if key
    current_user.update!(settings: settings)
  end

  def valid_target?(kind, id)
    scope = kind == 'team' ? user_teams : current_user.dashboards
    scope.exists?(id: id)
  end
end
