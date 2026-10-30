# Per-user landing page: the last-used team's issues board (default), a specific team's issues board,
# one of the user's saved views, or one of their dashboards. Stored in users.settings as home_team_id /
# home_view_id / home_dashboard_id (at most one is set; see User#set_home_page); the form posts a single
# `home` value like "team:3", "view:7" or "dashboard:5", blank for default.
class Settings::HomePageController < ApplicationController
  def update
    kind, id = params[:home].to_s.split(':', 2)

    unless current_user.set_home_page(kind, id, within_teams: user_teams)
      redirect_to settings_path(section: 'home_page'), alert: 'Unknown home page.', status: :see_other and return
    end

    redirect_to settings_path(section: 'home_page'), notice: 'Home page saved', status: :see_other
  end
end
