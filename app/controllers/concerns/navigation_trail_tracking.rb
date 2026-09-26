# Keeps the session's NavigationTrail current. The trail is fed from the referer — the page the user
# is actually on — rather than from the requested URL, because:
# - index filters are pushState()d into the URL without a full navigation, so only the referer
#   carries them;
# - Turbo prefetches links on hover, so a requested URL may never be visited, and a visited page
#   may be served from the prefetch cache without reaching the server.
# The page being rendered is folded in only in memory (see NavigationTrail#back_from); it lands in
# the session once a request is made from it.
module NavigationTrailTracking
  extend ActiveSupport::Concern

  SESSION_KEY = :navigation_trail

  included do
    before_action :record_navigation_referer, if: :authenticated?
    helper_method :navigation_back_path
  end

  private

  def navigation_trail
    @navigation_trail ||= NavigationTrail.new(session[SESSION_KEY])
  end

  def record_navigation_referer
    referer = same_origin_referer_fullpath
    return unless referer

    entries = navigation_trail.visit(referer).entries
    session[SESSION_KEY] = entries unless session[SESSION_KEY] == entries
  end

  def same_origin_referer_fullpath
    return if request.referer.blank?

    uri = URI.parse(request.referer)
    return unless uri.host == request.host && uri.port == request.port

    [uri.path, uri.query].compact.join('?')
  rescue URI::InvalidURIError
    nil
  end

  # Back target for the top bar of the page being rendered.
  def navigation_back_path
    navigation_trail.back_from(request.fullpath, team_id: current_team&.id)
  end

  # Where to send the user after finishing an action (creating or deleting an issue). Prefers an
  # explicit `return_to` param — captured when the form rendered, so another tab moving the trail
  # doesn't redirect this one somewhere unexpected — then the trail. `leaving` is the page being
  # left for good (a deleted issue), which must not be returned to.
  def navigation_return_path(leaving: nil)
    return_to_path || navigation_trail.back_from(leaving, team_id: current_team&.id)
  end

  # The `return_to` param alone, only when it points at a page on the current team.
  def return_to_path
    requested = params[:return_to].to_s
    requested if NavigationTrail.team_id_of(requested) == current_team&.id&.to_s
  end
end
