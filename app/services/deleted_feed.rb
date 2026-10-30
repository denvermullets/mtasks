# Tombstones for the desktop sync: records destroyed since a given time, read from paper_trail
# `destroy` versions. A version's `object` holds the row as it was, so ownership (team, user) is
# found there rather than through the (now gone) record.
#
# Subclasses name an owner and a SOURCES list and implement `scope_source(versions, source)`, which
# narrows that source's destroy versions to the owner. To expose another record type, add a Source
# to the subclass's SOURCES and give the model `has_paper_trail on: :destroy` (or full tracking).
class DeletedFeed
  # `scope` is a lambda that receives the destroy versions of `item_type` plus the feed's owner
  # context (see the subclasses) and returns the narrowed relation.
  Source = Struct.new(:item_type, :scope, keyword_init: true)

  def initialize(owner, since: nil)
    @owner = owner
    @since = since
  end

  # [{ record_type:, record_id:, deleted_at: }], oldest deletion first.
  def entries
    versions.map do |v|
      { record_type: v.item_type, record_id: v.item_id, deleted_at: v.created_at.utc.iso8601(6) }
    end
  end

  private

  def versions
    base = PaperTrail::Version.where(event: 'destroy')
    base = base.where(created_at: @since..) if @since
    scoped = self.class::SOURCES.map { |s| scope_source(base.where(item_type: s.item_type), s) }
    scoped.reduce { |a, b| a.or(b) }.order(:created_at, :id)
  end

  def scope_source(_versions, _source)
    raise NotImplementedError
  end
end
