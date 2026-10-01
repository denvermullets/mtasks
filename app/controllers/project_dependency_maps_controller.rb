class ProjectDependencyMapsController < ApplicationController
  include TeamScoped

  def show
    # current_team is nil when the URL names a team the user isn't on.
    raise ActiveRecord::RecordNotFound unless current_team

    @project = current_team.projects.find(params[:project_id])
    # Active by default; ?show=all brings back completed and canceled issues.
    @show_all = params[:show] == 'all'
    @graph = ProjectDependencyGraphQuery.call(project: @project, active_only: !@show_all)
  end
end
