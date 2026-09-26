# The in-app pages a session has recently been on, oldest first, as path + query strings. Backs the
# top-bar back links and the post-create/delete redirects so they return to where the user came from
# (including index filters, which live in the query string) instead of a hard-coded index page.
#
# Each page appears at most once: visiting a page already on the trail drops everything after it.
# That is what breaks the A -> B -> A back-link loop a plain referer produces.
#
# Stored in the cookie session, so it is capped by entry count and path length.
class NavigationTrail
  MAX_ENTRIES = 6
  MAX_PATH_LENGTH = 300

  # Pages worth returning to. Project tabs share a pattern so they count as one page.
  PAGES = [
    %r{\A/teams/(?<team>\d+)/issues/?\z},
    %r{\A/teams/(?<team>\d+)/issues/(?<id>\d+)/?\z},
    %r{\A/teams/(?<team>\d+)/issues/(?<id>\d+)/dependency_map/?\z},
    %r{\A/teams/(?<team>\d+)/projects/?\z},
    %r{\A/teams/(?<team>\d+)/projects/(?<id>\d+)(?:/(?:overview|discussion|activity))?/?\z},
    %r{\A/teams/(?<team>\d+)/roadmap/?\z}
  ].freeze

  # [page pattern index, team id, record id] — equal keys are the same page regardless of query.
  def self.page_key(fullpath)
    path = fullpath.to_s.split('?', 2).first
    PAGES.each_with_index do |pattern, index|
      match = pattern.match(path)
      return [index, match[:team], match.names.include?('id') ? match[:id] : nil] if match
    end
    nil
  end

  def self.trackable?(fullpath)
    page_key(fullpath).present?
  end

  def self.team_id_of(fullpath)
    page_key(fullpath)&.second
  end

  attr_reader :entries

  def initialize(entries)
    @entries = Array(entries).select { |entry| entry.is_a?(String) && self.class.trackable?(entry) }
  end

  def visit(fullpath)
    key = self.class.page_key(fullpath)
    return self unless key

    @entries = [] if entries.any? && self.class.team_id_of(entries.last) != key.second
    @entries = (entries_before(key) + [storable(fullpath)]).last(MAX_ENTRIES)
    self
  end

  # Where "back" goes from `fullpath`: the most recent entry for another page on the given team,
  # ignoring anything visited after `fullpath` itself. `fullpath` may be nil or an untracked page
  # (a form, say), in which case this is simply the most recent entry.
  def back_from(fullpath, team_id:)
    key = self.class.page_key(fullpath)
    candidates = key ? entries_before(key) : entries
    candidates.rfind { |entry| self.class.team_id_of(entry) == team_id.to_s }
  end

  private

  def entries_before(key)
    index = entries.rindex { |entry| self.class.page_key(entry) == key }
    index ? entries.first(index) : entries
  end

  def storable(fullpath)
    fullpath.length > MAX_PATH_LENGTH ? fullpath.split('?', 2).first : fullpath
  end
end
