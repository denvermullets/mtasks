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

      # Serializes any timeline entry ({type:, record:}) from IssueActivityFeed, relative to `issue`.
      def self.for(entry, issue:)
        record = entry[:record]
        base = { type: entry[:type].to_s, id: record.id, cursor: IssueActivityFeed.cursor_for(entry),
                 created_at: record.created_at.iso8601 }
        case entry[:type]
        when :version then new(record).as_json.merge(cursor: base[:cursor])
        when :dependency then base.merge(dependency_json(record, issue))
        when :comment then base.merge(comment: CommentSerializer.new(record, include_replies: false).as_json)
        when :reference then base.merge(reference_json(record))
        end
      end

      def self.user_json(user)
        user && { id: user.id, name: user.name }
      end

      def self.dependency_json(version, issue)
        data = version.event == 'destroy' ? (version.object || {}) : stored_values(version)
        blocking_id = data['blocking_issue_id']
        kind = data['kind'] || 'blocks'
        other_id = blocking_id == issue.id ? data['blocked_issue_id'] : blocking_id
        other = Issue.find_by(id: other_id)
        { event: version.event, kind: kind, direction: direction(kind, blocking_id == issue.id),
          other_issue: other && { id: other.id, identifier: other.identifier, title: other.title },
          actor: user_json(User.find_by(id: version.whodunnit)),
          description: VersionDescriptionService.call(version) }
      end

      def self.stored_values(version)
        (version.object_changes || {}).transform_values { |v| v.is_a?(Array) ? v.last : v }
      end

      def self.direction(kind, issue_is_source)
        case kind
        when 'relates' then 'relates'
        when 'duplicates' then issue_is_source ? 'duplicates' : 'duplicated_by'
        else issue_is_source ? 'blocking' : 'blocked_by'
        end
      end

      def self.reference_json(reference)
        source = reference.source_issue
        { source_issue: { id: source.id, identifier: source.identifier, title: source.title },
          source_type: reference.source_type, user: user_json(reference.user) }
      end

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
