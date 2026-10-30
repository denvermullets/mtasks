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

  # Resolves a version to a team through a parent id stored in `object`. The parent may be gone
  # too when it was deleted in the same cascade, so its own destroy version is checked as well.
  # Stays a relation so it can be OR'd with the other sources.
  PARENT_TEAM_SCOPE = lambda { |parent_type, table, key|
    lambda { |versions, team|
      live = "SELECT id FROM #{table} WHERE team_id = :team"
      gone = "SELECT item_id FROM versions WHERE item_type = :type AND event = 'destroy' " \
             "AND object ->> 'team_id' = :team_s"
      versions.where("(versions.object ->> '#{key}')::bigint IN (#{live} UNION #{gone})",
                     team: team.id, team_s: team.id.to_s, type: parent_type)
    }
  }

  # A comment belongs to exactly one of issue or project.
  COMMENT_SCOPE = lambda { |versions, team|
    PARENT_TEAM_SCOPE.call('Issue', 'issues', 'issue_id').call(versions, team)
                     .or(PARENT_TEAM_SCOPE.call('Project', 'projects', 'project_id').call(versions, team))
  }

  # Blocking and blocked issues share a team, so the blocking side is enough.
  DEPENDENCY_SCOPE = PARENT_TEAM_SCOPE.call('Issue', 'issues', 'blocking_issue_id')

  SOURCES = [
    Source.new(item_type: 'Issue', scope: TEAM_ID_SCOPE),
    Source.new(item_type: 'Project', scope: TEAM_ID_SCOPE),
    Source.new(item_type: 'Comment', scope: COMMENT_SCOPE),
    Source.new(item_type: 'IssueDependency', scope: DEPENDENCY_SCOPE),
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
