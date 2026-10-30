module Api
  module V1
    # Serializes one Project version in the same shape as ActivityEntrySerializer's version entries:
    # structured from/to changes with related ids resolved to names, plus a plain-text description.
    class ProjectActivityEntrySerializer
      FIELDS = %w[name description status priority lead_id start_date due_date roadmap_commitment].freeze
      LABELS = { 'lead_id' => 'lead', 'start_date' => 'start date', 'due_date' => 'due date',
                 'roadmap_commitment' => 'roadmap commitment' }.freeze

      def initialize(version)
        @version = version
        @changes = version.object_changes || {}
      end

      def as_json(*)
        { type: 'version', id: @version.id, cursor: "version:#{@version.id}",
          created_at: @version.created_at.iso8601, actor: actor, event: @version.event,
          changes: changes, description: description }
      end

      private

      def changed_fields
        FIELDS.select { |f| @changes.key?(f) }
      end

      def changes
        changed_fields.map do |field|
          from, to = @changes[field]
          { field: field, from: resolve(field, from), to: resolve(field, to) }
        end
      end

      def description
        return 'updated the project' if changed_fields.empty?

        "changed #{changed_fields.map { |f| LABELS.fetch(f, f) }.join(', ')}"
      end

      def resolve(field, value)
        return value if value.nil? || field != 'lead_id'

        { id: value, name: User.find_by(id: value)&.name }
      end

      def actor
        return if @version.whodunnit.blank?

        ActivityEntrySerializer.user_json(User.find_by(id: @version.whodunnit))
      end
    end
  end
end
