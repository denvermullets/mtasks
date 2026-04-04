class VersionDescriptionService < Service
  TRACKED_ATTRIBUTES = %w[
    lane_id assignee_id priority title description
    estimate due_date project_id milestone_id parent_issue_id
  ].freeze

  def initialize(version)
    @version = version
    @changes = version.object_changes || {}
  end

  def call
    return describe_dependency if @version.item_type == 'IssueDependency'

    descriptions = TRACKED_ATTRIBUTES.filter_map { |attr| describe_attribute(attr) }
    descriptions.empty? ? 'updated the issue' : descriptions.join(', ')
  end

  def self.timeline(issue)
    versions = issue.versions.where.not(event: 'create')
    comments = issue.comments.top_level.includes(:user)
    dep_versions = dependency_versions(issue)

    entries = versions.map { |v| { type: :version, record: v, created_at: v.created_at } }
    dep_versions.each { |v| entries << { type: :version, record: v, created_at: v.created_at } }
    comments.each { |c| entries << { type: :comment, record: c, created_at: c.created_at } }

    entries.sort_by { |e| e[:created_at] }
  end

  def self.dependency_versions(issue)
    id = issue.id
    PaperTrail::Version.where(item_type: 'IssueDependency').where(
      "object_changes -> 'blocking_issue_id' @> :arr OR object_changes -> 'blocked_issue_id' @> :arr " \
      "OR object ->> 'blocking_issue_id' = :id_str OR object ->> 'blocked_issue_id' = :id_str",
      arr: "[#{id}]", id_str: id.to_s
    )
  end
  private_class_method :dependency_versions

  private

  def describe_attribute(attr)
    return unless @changes.key?(attr)

    old_val, new_val = @changes[attr]
    send(:"describe_#{attr}", old_val, new_val)
  end

  def describe_lane_id(old_val, new_val)
    old_name = h(Lane.find_by(id: old_val)&.name || 'Unknown')
    new_name = h(Lane.find_by(id: new_val)&.name || 'Unknown')
    "changed status from <strong>#{old_name}</strong> to <strong>#{new_name}</strong>"
  end

  def describe_assignee_id(old_val, new_val)
    if new_val.nil?
      "unassigned <strong>#{h(user_name(old_val))}</strong>"
    elsif old_val.nil?
      "assigned to <strong>#{h(user_name(new_val))}</strong>"
    else
      "reassigned from <strong>#{h(user_name(old_val))}</strong> " \
        "to <strong>#{h(user_name(new_val))}</strong>"
    end
  end

  def describe_priority(old_val, new_val)
    old_label = h(old_val&.to_s&.titleize || 'None')
    new_label = h(new_val&.to_s&.titleize || 'None')
    "changed priority from <strong>#{old_label}</strong> to <strong>#{new_label}</strong>"
  end

  def describe_title(_old_val, _new_val)
    'changed the title'
  end

  def describe_description(_old_val, _new_val)
    'updated the description'
  end

  def describe_estimate(old_val, new_val)
    "changed estimate from <strong>#{h(old_val || 'none')}</strong> " \
      "to <strong>#{h(new_val || 'none')}</strong>"
  end

  def describe_due_date(old_val, new_val)
    "changed due date from <strong>#{h(old_val || 'none')}</strong> " \
      "to <strong>#{h(new_val || 'none')}</strong>"
  end

  def describe_project_id(_old_val, new_val)
    new_name = h(Project.find_by(id: new_val)&.name || 'None')
    "moved to project <strong>#{new_name}</strong>"
  end

  def describe_milestone_id(_old_val, new_val)
    new_name = h(Milestone.find_by(id: new_val)&.name || 'None')
    "changed milestone to <strong>#{new_name}</strong>"
  end

  def describe_parent_issue_id(_old_val, _new_val)
    'changed parent issue'
  end

  def describe_dependency
    ids = dependency_issue_ids
    blocking_name = h(issue_identifier(ids[:blocking]) || 'Unknown')
    blocked_name = h(issue_identifier(ids[:blocked]) || 'Unknown')
    action = @version.event == 'destroy' ? 'removed' : 'added'

    "#{action} dependency: <strong>#{blocking_name}</strong> blocking <strong>#{blocked_name}</strong>"
  end

  def dependency_issue_ids
    data = @version.event == 'destroy' ? (@version.object || {}) : @changes
    if @version.event == 'destroy'
      { blocking: data['blocking_issue_id'], blocked: data['blocked_issue_id'] }
    else
      { blocking: data['blocking_issue_id']&.last, blocked: data['blocked_issue_id']&.last }
    end
  end

  def issue_identifier(id)
    Issue.find_by(id: id)&.identifier
  end

  def user_name(id)
    User.find_by(id: id)&.name || 'Unknown'
  end

  def h(str)
    ERB::Util.html_escape(str)
  end
end
