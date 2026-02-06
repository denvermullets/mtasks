class NotificationService < Service
  def initialize(issue:, actor:, action:, version: nil, comment: nil)
    @issue = issue
    @actor = actor
    @action = action
    @version = version
    @comment = comment
  end

  def call
    recipients.each do |recipient|
      Notification.create!(
        user: recipient,
        actor: @actor,
        issue: @issue,
        version_id: @version&.id,
        comment: @comment,
        action: @action,
        message: build_message
      )
    end
  end

  def self.action_for_version(version)
    changes = version.object_changes || {}

    if changes.key?('lane_id') then 'changed_status'
    elsif changes.key?('assignee_id') then 'changed_assignee'
    elsif changes.key?('priority') then 'changed_priority'
    else 'updated'
    end
  end

  private

  def recipients
    users = []
    users << @issue.creator if @issue.creator
    users << @issue.assignee if @issue.assignee
    users.uniq.reject { |u| u == @actor }
  end

  def build_message
    identifier = @issue.identifier
    desc = action_description
    "#{@actor.name} #{desc} on #{identifier}"
  end

  def action_description
    case @action
    when 'commented' then 'commented'
    when 'changed_status' then version_field_description('lane_id', method(:lane_names))
    when 'changed_assignee' then version_field_description('assignee_id', method(:assignee_names))
    when 'changed_priority' then version_field_description('priority', method(:priority_labels))
    else 'updated'
    end
  end

  def version_field_description(field, name_resolver)
    changes = @version&.object_changes
    return "changed #{field.chomp('_id')}" unless changes&.key?(field)

    old_val, new_val = changes[field]
    old_name, new_name = name_resolver.call(old_val, new_val)
    "changed #{field.chomp('_id')} from #{old_name} to #{new_name}"
  end

  def lane_names(old_val, new_val)
    [
      Lane.find_by(id: old_val)&.name || 'Unknown',
      Lane.find_by(id: new_val)&.name || 'Unknown'
    ]
  end

  def assignee_names(old_val, new_val)
    [
      User.find_by(id: old_val)&.name || 'Unassigned',
      User.find_by(id: new_val)&.name || 'Unassigned'
    ]
  end

  def priority_labels(old_val, new_val)
    [
      old_val&.to_s&.titleize || 'None',
      new_val&.to_s&.titleize || 'None'
    ]
  end
end
