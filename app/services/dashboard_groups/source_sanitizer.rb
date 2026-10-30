module DashboardGroups
  # Narrows client-submitted group sources to what the user may actually use. Shared by the web and
  # API group controllers so both drop inaccessible teams, projects and labels the same way, silently.
  # `teams` is the set the caller can reach (the web: the user's non-archived teams; the API: that
  # set narrowed by the token's team scope). `all_*` ids only count when they're also sources.
  #
  # Returns keyword args for DashboardGroup#replace_sources!.
  class SourceSanitizer < Service
    KEYS = %i[team_ids project_ids label_ids all_team_ids all_project_ids].freeze

    def initialize(teams:, params:)
      @team_ids = teams.pluck(:id)
      @params = params
    end

    def call
      team_ids = submitted(:team_ids) & @team_ids
      project_ids = scoped_ids(Project, :project_ids)
      {
        team_ids: team_ids, project_ids: project_ids, label_ids: scoped_ids(Label, :label_ids),
        all_team_ids: submitted(:all_team_ids) & team_ids,
        all_project_ids: submitted(:all_project_ids) & project_ids
      }
    end

    private

    # collection_check_boxes posts a blank entry so the key is always present; drop it.
    def submitted(key)
      Array(@params[key]).map(&:to_i).reject(&:zero?)
    end

    def scoped_ids(model, key)
      ids = submitted(key)
      return [] if ids.empty?

      model.where(id: ids, team_id: @team_ids).pluck(:id)
    end
  end
end
