class IssueDependenciesController < ApplicationController
  include TeamScoped

  before_action :set_issue

  def search
    issues = search_candidates(params[:q].to_s.strip)
    render partial: 'issue_dependencies/search_results', locals: { issues: issues }
  end

  def bulk_create
    target_ids = Array(params[:target_issue_ids]).map(&:to_i).uniq
    direction = params[:direction]

    # count rather than each: one event carries the bulk size, never one event per row.
    errors = []
    linked = target_ids.count do |target_id|
      target_issue = current_team.issues.find_by(id: target_id)
      next false unless target_issue

      dependency = IssueDependencies::Link.call(issue: @issue, target: target_issue, direction: direction)
      errors.concat(dependency.errors.full_messages)
      dependency.persisted?
    end
    track_dependency_link(direction, linked)

    render_relations(alert: errors.first)
  end

  def create
    target_issue = current_team.issues.find(params[:target_issue_id])
    direction = params[:direction]

    dependency = IssueDependencies::Link.call(issue: @issue, target: target_issue, direction: direction)

    track_dependency_link(direction, 1) if dependency.persisted?
    render_relations(alert: dependency.errors.full_messages.first)
  end

  def destroy
    dependency = find_dependency

    if dependency && (dependency.blocking_issue_id == @issue.id || dependency.blocked_issue_id == @issue.id)
      dependency.destroy
      track_feature('issue-dependency', 'unlink', direction: link_direction(dependency))
      render_relations
    else
      head :not_found
    end
  end

  private

  # params[:id] is either the join-record id or the other issue's id, depending on which button
  # in the relations partial was used. Looks across every link kind.
  def find_dependency
    @issue.outgoing_links.find_by(id: params[:id]) ||
      @issue.incoming_links.find_by(id: params[:id]) ||
      @issue.outgoing_links.find_by(blocked_issue_id: params[:id]) ||
      @issue.incoming_links.find_by(blocking_issue_id: params[:id])
  end

  # `direction` names which side of the link the acting issue is on (taxonomy §5.2, amended by
  # VEK-584) — never which issues, which would be raw record ids.
  def track_dependency_link(direction, count)
    return unless count.positive?

    track_feature('issue-dependency', 'link',
                  direction: IssueDependencies::Link.normalize_direction(direction), count: count)
  end

  def link_direction(dependency)
    IssueDependencies::Link.direction_for(dependency, @issue)
  end

  def search_candidates(query)
    # Any existing link, of any kind, rules the pair out (IssueDependency#not_already_linked).
    exclude_ids = [@issue.id] + @issue.outgoing_links.pluck(:blocked_issue_id) +
                  @issue.incoming_links.pluck(:blocking_issue_id)
    current_team.issues.not_archived.not_completed
                .where(canceled_at: nil)
                .where.not(id: exclude_ids).order(:team_number)
                .matching_search(query)
                .limit(20)
  end

  def set_issue
    @issue = find_issue_with_links(params[:issue_id])
  end

  def find_issue_with_links(id)
    current_team.issues.with_links.find(id)
  end

  # `alert` surfaces a validation error (cycle, already linked) inside the frame.
  def render_relations(alert: nil)
    # Re-fetch rather than reload so the partial still gets preloaded links after a change.
    @issue = find_issue_with_links(@issue.id)

    # The sidebar is rendered twice on the issue show page (desktop + mobile),
    # so both relations frames must be replaced to update whichever one is visible.
    render turbo_stream: [
      turbo_stream.replace(
        'issue_relations',
        partial: 'issue_dependencies/relations',
        locals: { issue: @issue, mobile: false, alert: alert }
      ),
      turbo_stream.replace(
        'issue_relations_mobile',
        partial: 'issue_dependencies/relations',
        locals: { issue: @issue, mobile: true, alert: alert }
      )
    ]
  end
end
