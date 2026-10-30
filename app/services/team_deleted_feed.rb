# Tombstones for records destroyed in a team since a given time (see DeletedFeed).
#
# A Source ties a version to a team: TEAM_ID_SCOPE matches `object.team_id`; records without a
# team id pass a `scope` lambda (given the versions relation and the team) that resolves it another
# way, for example through the parent issue or project id stored in `object`.
class TeamDeletedFeed < DeletedFeed
  TEAM_ID_SCOPE = lambda { |versions, team|
    versions.where("versions.object ->> 'team_id' = ?", team.id.to_s)
  }

  # Resolves a version to a team through a parent id stored in `object`. The parent may be gone
  # too when it was deleted in the same cascade, so its own destroy version is checked as well.
  # Stays a relation so it can be OR'd with the other sources.
  PARENT_TEAM_SCOPE = lambda { |parent_class, key|
    lambda { |versions, team|
      live = parent_class.where(team_id: team.id).select(:id)
      gone = PaperTrail::Version.where(item_type: parent_class.name, event: 'destroy')
                                .where("versions.object ->> 'team_id' = ?", team.id.to_s)
                                .select(:item_id)
      versions.where('(versions.object ->> ?)::bigint IN (?) OR (versions.object ->> ?)::bigint IN (?)',
                     key, live, key, gone)
    }
  }

  # A comment belongs to exactly one of issue or project.
  COMMENT_SCOPE = lambda { |versions, team|
    PARENT_TEAM_SCOPE.call(Issue, 'issue_id').call(versions, team)
                     .or(PARENT_TEAM_SCOPE.call(Project, 'project_id').call(versions, team))
  }

  # Blocking and blocked issues share a team, so the blocking side is enough.
  DEPENDENCY_SCOPE = PARENT_TEAM_SCOPE.call(Issue, 'blocking_issue_id')

  SOURCES = [
    Source.new(item_type: 'Issue', scope: TEAM_ID_SCOPE),
    Source.new(item_type: 'Project', scope: TEAM_ID_SCOPE),
    Source.new(item_type: 'Comment', scope: COMMENT_SCOPE),
    Source.new(item_type: 'IssueDependency', scope: DEPENDENCY_SCOPE),
    Source.new(item_type: 'Label', scope: TEAM_ID_SCOPE),
    Source.new(item_type: 'RecurringIssue', scope: TEAM_ID_SCOPE)
  ].freeze

  private

  def scope_source(versions, source)
    source.scope.call(versions, @owner)
  end
end
