# Tombstones for records destroyed in a team since a given time (see DeletedFeed).
#
# A Source ties a version to a team: TEAM_ID_SCOPE matches `object.team_id`; records without a
# team id pass a `scope` lambda (given the versions relation and the team) that resolves it another
# way, for example through the parent issue or project id stored in `object`.
class TeamDeletedFeed < DeletedFeed
  TEAM_ID_SCOPE = lambda { |versions, team|
    versions.where("versions.object ->> 'team_id' = ?", team.id.to_s)
  }

  SOURCES = [
    Source.new(item_type: 'Issue', scope: TEAM_ID_SCOPE),
    Source.new(item_type: 'Project', scope: TEAM_ID_SCOPE)
  ].freeze

  private

  def scope_source(versions, source)
    source.scope.call(versions, @owner)
  end
end
