# Tombstones for the desktop sync: records destroyed in a team since a given time, read from
# paper_trail `destroy` versions. A version's `object` holds the row as it was, so the team is
# found there rather than through the (now gone) record.
#
# To expose another record type, add a Source to SOURCES and give the model
# `has_paper_trail on: :destroy` (or full tracking). A Source names how a version of that type
# is tied to a team: TEAM_ID_SCOPE matches `object.team_id`; records without a team id pass a
# `scope` lambda (given the versions relation and the team) that resolves it another way, for
# example through the parent issue or project id stored in `object`.
class TeamDeletedFeed
  Source = Struct.new(:item_type, :scope, keyword_init: true)

  TEAM_ID_SCOPE = lambda { |versions, team|
    versions.where("versions.object ->> 'team_id' = ?", team.id.to_s)
  }

  SOURCES = [
    Source.new(item_type: 'Issue', scope: TEAM_ID_SCOPE),
    Source.new(item_type: 'Project', scope: TEAM_ID_SCOPE),
    Source.new(item_type: 'Label', scope: TEAM_ID_SCOPE)
  ].freeze

  def initialize(team, since: nil)
    @team = team
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
    scoped = SOURCES.map { |s| s.scope.call(base.where(item_type: s.item_type), @team) }
    scoped.reduce { |a, b| a.or(b) }.order(:created_at, :id)
  end
end
