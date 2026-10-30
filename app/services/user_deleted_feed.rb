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

  # Dashboards have no team, so they are not limited by `team_ids`.
  DASHBOARD_SCOPE = lambda { |versions, user, _team_ids|
    versions.where("versions.object ->> 'user_id' = ?", user.id.to_s)
  }

  # Groups carry only `dashboard_id`; their owner is the dashboard's, which may itself be gone
  # (a dashboard delete cascades to its groups), so check live rows and Dashboard tombstones.
  DASHBOARD_GROUP_SCOPE = lambda { |versions, user, _team_ids|
    live = Dashboard.where(user_id: user.id).select(:id)
    gone = PaperTrail::Version.where(item_type: 'Dashboard', event: 'destroy')
                              .where("versions.object ->> 'user_id' = ?", user.id.to_s)
                              .select(:item_id)
    versions.where("(versions.object ->> 'dashboard_id')::bigint IN (?)", live)
            .or(versions.where("(versions.object ->> 'dashboard_id')::bigint IN (?)", gone))
  }

  SOURCES = [
    Source.new(item_type: 'SavedView', scope: USER_ID_SCOPE),
    Source.new(item_type: 'Dashboard', scope: DASHBOARD_SCOPE),
    Source.new(item_type: 'DashboardGroup', scope: DASHBOARD_GROUP_SCOPE)
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
