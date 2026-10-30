module Api
  module V1
    # Config only: the desktop evaluates issues locally. Group sources outside `allowed` are left out,
    # so a token never learns about teams, projects or labels it can't reach.
    # `allowed` is { 'Team' => ids, 'Project' => ids, 'Label' => ids }.
    class DashboardSerializer
      def initialize(dashboard, allowed:)
        @dashboard = dashboard
        @allowed = allowed
      end

      def as_json
        {
          id: @dashboard.id, name: @dashboard.name, description: @dashboard.description,
          position: @dashboard.position, updated_at: @dashboard.updated_at,
          groups: @dashboard.groups.map { |group| serialize_group(group) }
        }
      end

      private

      def serialize_group(group)
        sources = group.sources.select { |s| @allowed.fetch(s.source_type, []).include?(s.source_id) }
        {
          id: group.id, name: group.name, description: group.description, color: group.color,
          position: group.position,
          team_ids: ids(sources, 'Team'), project_ids: ids(sources, 'Project'), label_ids: ids(sources, 'Label'),
          all_team_ids: ids(sources, 'Team', all: true), all_project_ids: ids(sources, 'Project', all: true)
        }
      end

      def ids(sources, type, all: false)
        sources.select { |s| s.source_type == type && (!all || s.include_all) }.map(&:source_id)
      end
    end
  end
end
