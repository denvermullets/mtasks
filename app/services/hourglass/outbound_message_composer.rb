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
      { body: fallback_body, data: data_payload }
    end

    private

    def data_payload
      base_data.merge(event_specific_data)
    end

    def base_data
      {
        source: 'mtasks',
        event_type: @event_type,
        source_url: source_url,
        actor_email: @actor&.email,
        actor_name: @actor&.name,
        actor_username: username_for(@actor),
        issue_id: @issue.id,
        identifier: @issue.identifier,
        title: @issue.title,
        team_slug: @issue.team&.identifier,
        project_id: @issue.project&.id,
        project_name: @issue.project&.name
      }.compact
    end

    def source_url
      return nil unless @issue.team

      "#{Hourglass::PublicUrl.base}#{Rails.application.routes.url_helpers.team_issue_path(@issue.team, @issue)}"
    end

    def event_specific_data
      case @event_type
      when 'issue.created'          then created_data
      when 'issue.status_changed'   then status_changed_data
      when 'issue.assigned'         then assigned_data
      when 'issue.priority_changed' then priority_changed_data
      else {}
      end
    end

    def created_data
      {
        priority: priority_label_for(@issue.priority),
        status_lane_name: @issue.lane&.name,
        labels: @issue.labels.map { |l| { name: l.name, color: l.color } }.presence
      }.merge(assignee_fields(@issue.assignee)).compact
    end

    def status_changed_data
      changes = @version&.object_changes
      return {} unless changes&.key?('lane_id')

      old_id, new_id = changes['lane_id']
      {
        from_lane_name: Lane.find_by(id: old_id)&.name,
        to_lane_name: Lane.find_by(id: new_id)&.name
      }.compact
    end

    def assigned_data
      changes = @version&.object_changes
      new_user_id = changes&.dig('assignee_id', 1) || @issue.assignee_id
      assignee_fields(User.find_by(id: new_user_id)).compact
    end

    def priority_changed_data
      changes = @version&.object_changes
      return { priority: priority_label_for(@issue.priority) }.compact unless changes&.key?('priority')

      _old_val, new_val = changes['priority']
      { priority: priority_label_for(new_val) }.compact
    end

    def assignee_fields(user)
      return {} unless user

      {
        assignee_email: user.email,
        assignee_name: user.name,
        assignee_username: username_for(user)
      }
    end

    def username_for(user)
      return nil unless user&.email

      user.email.split('@').first
    end

    def priority_label_for(value)
      return nil if value.nil?

      key = value.is_a?(Integer) ? Issue.priorities.key(value) : value.to_s
      key.to_s.gsub('_', ' ').presence
    end

    def fallback_body
      case @event_type
      when 'issue.created'          then "#{@issue.identifier} created by #{actor_name}: #{@issue.title}"
      when 'issue.status_changed'   then change_fallback('lane_id', method(:lane_names), 'moved')
      when 'issue.assigned'         then change_fallback('assignee_id', method(:assignee_names), 'reassigned')
      when 'issue.priority_changed' then change_fallback('priority', method(:priority_labels), 'priority')
      else "#{@issue.identifier} updated by #{actor_name}"
      end
    end

    def change_fallback(field, name_resolver, verb)
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
      [priority_fallback_label(old_val), priority_fallback_label(new_val)]
    end

    def priority_fallback_label(val)
      return 'None' if val.nil?

      key = val.is_a?(Integer) ? Issue.priorities.key(val) : val.to_s
      key.to_s.titleize.presence || 'None'
    end
  end
end
