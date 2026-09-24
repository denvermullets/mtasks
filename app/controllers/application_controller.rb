class ApplicationController < ActionController::Base
  include Authentication
  include TeamScoped
  include NavigationTrailTracking
  include VektisTracking

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :configure_paper_trail_whodunnit

  helper_method :sidebar_dashboards

  private

  # Loaded once per request; the desktop sidebar and the mobile drawer both render it.
  def sidebar_dashboards
    @sidebar_dashboards ||= current_user.dashboards.to_a
  end

  def configure_paper_trail_whodunnit
    ::PaperTrail.request.whodunnit = Current.user&.id&.to_s
  end

  def redirect_if_authenticated
    return unless authenticated?

    team_id = current_team&.id || current_user.teams.not_archived.first&.id
    redirect_to team_id ? team_issues_path(team_id) : new_team_path
  end

  # Assigning to a has_many_attached replaces every existing file (and a blank submission purges them),
  # so edits append uploads instead.
  def attach_new_files(record, files)
    uploads = Array(files).compact_blank
    record.files.attach(uploads) if uploads.any?
  end
end
