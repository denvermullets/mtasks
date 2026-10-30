# Tombstones for the current user's own records destroyed since a given time (see DeletedFeed).
#
# To expose another user-owned type, add one Source to SOURCES. USER_ID_SCOPE matches
# `object.user_id`; records tied to a team (`object.team_id`) are further limited to `team_ids`,
# the teams the caller's token can see. Records owned differently pass their own `scope` lambda,
# given (versions, user, team_ids).
class UserDeletedFeed < DeletedFeed
  USER_ID_SCOPE = lambda { |versions, user, team_ids|
    versions.where("versions.object ->> 'user_id' = ?", user.id.to_s)
            .where("(versions.object ->> 'team_id')::bigint IN (?)", team_ids)
  }

  SOURCES = [
    Source.new(item_type: 'SavedView', scope: USER_ID_SCOPE)
  ].freeze

  # team_ids: ids of the teams the caller can see (all of the user's teams for a full token).
  def initialize(user, team_ids:, since: nil)
    super(user, since: since)
    @team_ids = team_ids
  end

  private

  def scope_source(versions, source)
    source.scope.call(versions, @owner, @team_ids)
  end
end
