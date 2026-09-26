# The user's own settings page: one two-column screen whose sections post to the per-preference
# controllers (Settings::AppearanceController, Settings::HomePageController, ...).
class Settings::AccountController < ApplicationController
  def show
    @themes = Settings::AppearanceController.theme_swatches
    @fonts = Settings::AppearanceController.font_options
    owned, joined = user_teams.partition { |t| team_owner?(t) }
    @owned_teams = current_user.order_teams(owned, :owned)
    @joined_teams = current_user.order_teams(joined, :joined)
    @dashboards = current_user.dashboards
    @saved_views = sidebar_saved_views
    @api_token_count = current_user.api_tokens.active.count
  end
end
