class DependencyMapsController < ApplicationController
  include TeamScoped

  DEFAULT_DEPTH = DependencyGraphQuery::DEFAULT_MAX_DEPTH
  MAX_DEPTH = 5

  def show
    # current_team is nil when the URL names a team the user isn't on.
    raise ActiveRecord::RecordNotFound unless current_team

    @issue = current_team.issues.find(params[:issue_id])
    @depth = params.fetch(:depth, DEFAULT_DEPTH).to_i.clamp(1, MAX_DEPTH)
    @graph = DependencyGraphQuery.call(issue: @issue, max_depth: @depth)
    @lanes = current_team.lanes.order(:position)
  end
end
