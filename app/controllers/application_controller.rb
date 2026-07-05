class ApplicationController < ActionController::Base
  include Authentication
  include TeamScoped

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :configure_paper_trail_whodunnit

  private

  def configure_paper_trail_whodunnit
    ::PaperTrail.request.whodunnit = Current.user&.id&.to_s
  end

  def redirect_if_authenticated
    return unless authenticated?

    team_id = current_team&.id || current_user.teams.not_archived.first&.id
    redirect_to team_id ? team_issues_path(team_id) : new_team_path
  end
end
