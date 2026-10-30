# The issue activity timeline as typed entries, oldest first, with since / limit / before_id paging
# and a type filter. Shared by the API; the web renders VersionDescriptionService.timeline.
#
# Entries are ordered by (created_at, type rank, id) so the order is total and stable. Record ids
# collide across types, so an entry's page cursor is "<type>:<id>".
class IssueActivityFeed < Service
  TYPES = %i[version dependency comment reference].freeze
  # Plural names are what the API takes in `types`.
  TYPE_ALIASES = { 'versions' => :version, 'dependencies' => :dependency,
                   'comments' => :comment, 'references' => :reference }.freeze
  DEFAULT_LIMIT = 100
  MAX_LIMIT = 500

  Page = Struct.new(:items, :next_before, keyword_init: true)

  def self.cursor_for(entry)
    "#{entry[:type]}:#{entry[:record].id}"
  end

  def self.parse_types(raw)
    return TYPES if raw.blank?

    raw.to_s.split(',').filter_map do |t|
      t = t.strip.downcase
      TYPE_ALIASES[t] || (t.to_sym if TYPES.map(&:to_s).include?(t))
    end.uniq
  end

  # since: Time or nil; before: "type:id" (a bare id means a version entry) or nil.
  def initialize(issue:, types: TYPES, since: nil, limit: nil, before: nil)
    @issue = issue
    @types = types
    @since = since
    @limit = limit.to_i.positive? ? [limit.to_i, MAX_LIMIT].min : DEFAULT_LIMIT
    @before = before
  end

  # Returns a Page, or nil when `before` names an entry that does not exist.
  def call
    all = all_entries.sort_by { |e| sort_key(e) }
    boundary = nil
    if @before.present?
      boundary = all.find { |e| self.class.cursor_for(e) == normalized_before }
      return unless boundary
    end

    entries = select_entries(all, boundary)
    older = entries.size > @limit
    entries = entries.last(@limit)
    Page.new(items: entries, next_before: (self.class.cursor_for(entries.first) if older))
  end

  private

  def select_entries(all, boundary)
    entries = all.select { |e| @types.include?(e[:type]) }
    entries = entries.select { |e| e[:record].created_at > @since } if @since
    entries = entries.select { |e| (sort_key(e) <=> sort_key(boundary)).negative? } if boundary
    entries
  end

  def normalized_before
    @before.to_s.include?(':') ? @before.to_s : "version:#{@before}"
  end

  def sort_key(entry)
    [entry[:record].created_at, TYPES.index(entry[:type]), entry[:record].id]
  end

  def all_entries
    entries(:version, VersionDescriptionService.version_entries(@issue)) +
      entries(:dependency, VersionDescriptionService.dependency_versions(@issue)) +
      entries(:comment, @issue.comments.top_level.includes(:user)) +
      entries(:reference, @issue.incoming_references.includes(:user, source_issue: :team))
  end

  def entries(type, records)
    records.map { |r| { type: type, record: r, created_at: r.created_at } }
  end
end
