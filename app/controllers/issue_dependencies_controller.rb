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

    target_ids.each do |target_id|
      target_issue = current_team.issues.find_by(id: target_id)
      next unless target_issue

      dependency = if direction == 'blocked_by'
                     IssueDependency.new(blocking_issue: target_issue, blocked_issue: @issue)
                   else
                     IssueDependency.new(blocking_issue: @issue, blocked_issue: target_issue)
                   end
      dependency.save
    end

    @issue.reload
    render_relations
  end

  def create
    target_issue = current_team.issues.find(params[:target_issue_id])
    direction = params[:direction]

    dependency = if direction == 'blocked_by'
                   IssueDependency.new(blocking_issue: target_issue, blocked_issue: @issue)
                 else
                   IssueDependency.new(blocking_issue: @issue, blocked_issue: target_issue)
                 end

    if dependency.save
      @issue.reload
      render_relations
    else
      head :unprocessable_entity
    end
  end

  def destroy
    dependency = IssueDependency.find_by(id: params[:id])

    dependency ||= @issue.blocking_dependencies.find_by(blocked_issue_id: params[:id]) ||
                   @issue.blocked_dependencies.find_by(blocking_issue_id: params[:id])

    if dependency && (dependency.blocking_issue_id == @issue.id || dependency.blocked_issue_id == @issue.id)
      dependency.destroy
      @issue.reload
      render_relations
    else
      head :not_found
    end
  end

  private

  def search_candidates(query)
    exclude_ids = [@issue.id] + @issue.blocked_issues.pluck(:id) + @issue.blocking_issues.pluck(:id)
    issues = current_team.issues.not_archived.not_completed
                         .where(canceled_at: nil)
                         .where.not(id: exclude_ids).order(:team_number)

    if query.present?
      issues = issues.joins(:team).where(
        "issues.title ILIKE :q OR CONCAT(teams.identifier, '-', issues.team_number::text) ILIKE :q",
        q: "%#{query}%"
      )
    end

    issues.limit(20)
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
