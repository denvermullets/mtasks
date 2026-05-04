module Hourglass
  class OutboundMessageComposer < Service
    EVENT_TYPES = %w[
      issue.created
      issue.updated
      issue.status_changed
      issue.assigned
      issue.priority_changed
    ].freeze

    def initialize(event_type:, issue:, actor:, version: nil)
      @event_type = event_type
      @issue = issue
      @actor = actor
      @version = version
    end

    def call
      case @event_type
      when 'issue.created'          then created_body
      when 'issue.status_changed'   then change_body('lane_id', method(:lane_names), 'moved')
      when 'issue.assigned'         then change_body('assignee_id', method(:assignee_names), 'reassigned')
      when 'issue.priority_changed' then change_body('priority', method(:priority_labels), 'priority')
      else updated_body
      end
    end

    private

    def created_body
      "#{@issue.identifier} created by #{actor_name}: #{@issue.title}"
    end

    def updated_body
      "#{@issue.identifier} updated by #{actor_name}"
    end

    def change_body(field, name_resolver, verb)
      changes = @version&.object_changes
      return "#{@issue.identifier} #{verb} by #{actor_name}" unless changes&.key?(field)

      old_val, new_val = changes[field]
      old_name, new_name = name_resolver.call(old_val, new_val)
      "#{@issue.identifier} #{verb} #{old_name} → #{new_name} by #{actor_name}"
    end

    def actor_name
      @actor&.name.presence || 'Someone'
    end

    def lane_names(old_val, new_val)
      [Lane.find_by(id: old_val)&.name || 'Unknown', Lane.find_by(id: new_val)&.name || 'Unknown']
    end

    def assignee_names(old_val, new_val)
      [User.find_by(id: old_val)&.name || 'Unassigned', User.find_by(id: new_val)&.name || 'Unassigned']
    end

    def priority_labels(old_val, new_val)
      [priority_label(old_val), priority_label(new_val)]
    end

    def priority_label(val)
      return 'None' if val.nil?

      key = val.is_a?(Integer) ? Issue.priorities.key(val) : val.to_s
      key.to_s.titleize.presence || 'None'
    end
  end
end
