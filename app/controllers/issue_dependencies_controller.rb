class IssueDependenciesController < ApplicationController
  include TeamScoped

  before_action :set_issue

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

  def set_issue
    @issue = current_team.issues.includes(:blocked_issues, :blocking_issues,
                                          :blocking_dependencies, :blocked_dependencies).find(params[:issue_id])
  end

  def render_relations
    render turbo_stream: turbo_stream.replace(
      'issue_relations',
      partial: 'issue_dependencies/relations',
      locals: { issue: @issue }
    )
  end
end
