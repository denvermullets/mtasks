class IssueDependenciesController < ApplicationController
  include TeamScoped
  include FormCollections

  before_action :set_issue
  before_action :load_form_collections, only: %i[create destroy]

  def create
    target_issue = current_team.issues.find(params[:target_issue_id])
    direction = params[:direction] # "blocking" or "blocked_by"

    dependency = if direction == 'blocked_by'
                   IssueDependency.new(blocking_issue: target_issue, blocked_issue: @issue)
                 else
                   IssueDependency.new(blocking_issue: @issue, blocked_issue: target_issue)
                 end

    if dependency.save
      @issue.reload
    else
      render turbo_stream: turbo_stream.append('errors', 'Error adding dependency'), status: :unprocessable_entity
    end
  end

  def destroy
    # Try finding by dependency ID first (from sidebar X button)
    dependency = IssueDependency.find_by(id: params[:id])

    # If not found, params[:id] might be a target issue ID (from picker unchecking)
    dependency ||= @issue.blocking_dependencies.find_by(blocked_issue_id: params[:id]) ||
                   @issue.blocked_dependencies.find_by(blocking_issue_id: params[:id])

    if dependency && (dependency.blocking_issue_id == @issue.id || dependency.blocked_issue_id == @issue.id)
      dependency.destroy
      @issue.reload
    else
      render turbo_stream: turbo_stream.append('errors', 'Dependency not found'), status: :not_found
    end
  end

  private

  def set_issue
    @issue = current_team.issues.find(params[:issue_id])
  end
end
