# The issue page's Sub-issues section: attach existing issues as sub-issues, detach one, and set
# or clear the issue's own parent. Everything re-renders the `issue_hierarchy` frame.
class SubIssuesController < ApplicationController
  include TeamScoped

  before_action :set_issue

  # ?mode=parent lists issues that could become this issue's parent; otherwise issues that
  # could become its sub-issues. Ancestors can't be children and descendants can't be the
  # parent, since either would close a loop.
  def search
    parent_mode = params[:mode] == 'parent'
    issues = current_team.issues.not_archived.where(canceled_at: nil)
                         .where.not(id: excluded_from_search(parent_mode))
                         .matching_search(params[:q].to_s.strip).includes(:team).order(:team_number).limit(20)
    render partial: 'sub_issues/search_results', locals: { issues: issues, parent_mode: parent_mode }
  end

  # Attaches each picked issue as a sub-issue of this one (reparenting it if it had a parent).
  def create
    errors = []
    linked = Array(params[:target_issue_ids]).map(&:to_i).uniq.count do |target_id|
      child = current_team.issues.find_by(id: target_id)
      next false unless child

      child.update(parent_issue: @issue).tap { |ok| errors.concat(child.errors.full_messages) unless ok }
    end
    track_feature('sub-issue', 'link', entity: 'issue', count: linked) if linked.positive?

    render_hierarchy(alert: errors.first)
  end

  # Detaches one sub-issue; it becomes top-level.
  def destroy
    child = @issue.sub_issues.find(params[:id])
    child.update!(parent_issue: nil)
    track_feature('sub-issue', 'unlink', entity: 'issue')

    render_hierarchy
  end

  # PATCH sets this issue's parent (parent_issue_id blank clears it).
  def parent
    previous = @issue.parent_issue_id
    @issue.parent_issue_id = params[:parent_issue_id].presence
    if @issue.save
      if @issue.parent_issue_id != previous
        track_feature('sub-issue', @issue.parent_issue_id ? 'link' : 'unlink', entity: 'issue')
      end
      render_hierarchy
    else
      render_hierarchy(alert: @issue.errors.full_messages.first)
    end
  end

  private

  def excluded_from_search(parent_mode)
    return [@issue.id, *@issue.descendant_ids, @issue.parent_issue_id].compact if parent_mode

    [@issue.id, *@issue.ancestor_ids, *@issue.sub_issue_ids]
  end

  def set_issue
    @issue = current_team.issues.find(params[:issue_id])
  end

  def render_hierarchy(alert: nil)
    render turbo_stream: turbo_stream.replace(
      'issue_hierarchy', partial: 'sub_issues/hierarchy', locals: { issue: @issue.reload, alert: alert }
    )
  end
end
