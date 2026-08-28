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
    linked = target_ids.count do |target_id|
      target_issue = current_team.issues.find_by(id: target_id)
      next false unless target_issue

      build_dependency(target_issue, direction).save
    end
    track_dependency_link(direction, linked)

    @issue.reload
    render_relations
  end

  def create
    target_issue = current_team.issues.find(params[:target_issue_id])
    direction = params[:direction]

    dependency = build_dependency(target_issue, direction)

    if dependency.save
      track_dependency_link(direction, 1)
      @issue.reload
      render_relations
    else
      head :unprocessable_entity
    end
  end

  def destroy
    dependency = find_dependency

    if dependency && (dependency.blocking_issue_id == @issue.id || dependency.blocked_issue_id == @issue.id)
      dependency.destroy
      track_feature('issue-dependency', 'unlink', direction: link_direction(dependency))
      @issue.reload
      render_relations
    else
      head :not_found
    end
  end

  private

  # params[:id] is either the join-record id or the other issue's id, depending on which button
  # in the relations partial was used.
  def find_dependency
    IssueDependency.find_by(id: params[:id]) ||
      @issue.blocking_dependencies.find_by(blocked_issue_id: params[:id]) ||
      @issue.blocked_dependencies.find_by(blocking_issue_id: params[:id])
  end

  def build_dependency(target_issue, direction)
    if direction == 'blocked_by'
      IssueDependency.new(blocking_issue: target_issue, blocked_issue: @issue)
    else
      IssueDependency.new(blocking_issue: @issue, blocked_issue: target_issue)
    end
  end

  # `direction` names which side of the link the acting issue is on (taxonomy §5.2, amended by
  # VEK-584) — never which issues, which would be raw record ids.
  def track_dependency_link(direction, count)
    return unless count.positive?

    track_feature('issue-dependency', 'link',
                  direction: direction == 'blocked_by' ? 'blocked_by' : 'blocking', count: count)
  end

  def link_direction(dependency)
    dependency.blocking_issue_id == @issue.id ? 'blocking' : 'blocked_by'
  end

  def search_candidates(query)
    exclude_ids = [@issue.id] + @issue.blocked_issues.pluck(:id) + @issue.blocking_issues.pluck(:id)
    current_team.issues.not_archived.not_completed
                .where(canceled_at: nil)
                .where.not(id: exclude_ids).order(:team_number)
                .matching_search(query)
                .limit(20)
  end

  def set_issue
    @issue = current_team.issues.includes(:blocked_issues, :blocking_issues,
                                          :blocking_dependencies, :blocked_dependencies).find(params[:issue_id])
  end

  def render_relations
    # The sidebar is rendered twice on the issue show page (desktop + mobile),
    # so both relations frames must be replaced to update whichever one is visible.
    render turbo_stream: [
      turbo_stream.replace(
        'issue_relations',
        partial: 'issue_dependencies/relations',
        locals: { issue: @issue, mobile: false }
      ),
      turbo_stream.replace(
        'issue_relations_mobile',
        partial: 'issue_dependencies/relations',
        locals: { issue: @issue, mobile: true }
      )
    ]
  end
end
