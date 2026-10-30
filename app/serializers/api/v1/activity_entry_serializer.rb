module Api
  module V1
    # Serializes one issue-history entry. Structured `changes` carry from/to values with related
    # ids resolved to names; `description` is the same English string the web timeline shows.
    class ActivityEntrySerializer
      REFERENCE_FIELDS = {
        'lane_id' => [Lane, :name],
        'assignee_id' => [User, :name],
        'project_id' => [Project, :name],
        'parent_issue_id' => [Issue, :identifier],
        'team_id' => [Team, :name]
      }.freeze

      def initialize(version)
        @version = version
        @changes = version.object_changes || {}
      end

      def as_json(*)
        {
          type: 'version',
          id: @version.id,
          created_at: @version.created_at.iso8601,
          actor: actor,
          event: @version.event,
          changes: changes,
          description: VersionDescriptionService.call(@version)
        }
      end

      private

      # A team move is described only as the move, matching the web timeline.
      def changes
        fields = @changes.key?('team_id') ? %w[team_id] : VersionDescriptionService::TRACKED_ATTRIBUTES
        fields.filter_map do |field|
          next unless @changes.key?(field)

          from, to = @changes[field]
          { field: field, from: resolve(field, from), to: resolve(field, to) }
        end
      end

      def resolve(field, value)
        return value if value.nil?

        model, attr = REFERENCE_FIELDS[field]
        return value unless model

        record = model.find_by(id: value)
        { id: value, attr => record&.public_send(attr) }
      end

      def actor
        return if @version.whodunnit.blank?

        user = User.find_by(id: @version.whodunnit)
        user && { id: user.id, name: user.name }
      end
    end
  end
end
