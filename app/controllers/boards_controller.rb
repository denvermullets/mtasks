class BoardsController < ApplicationController
  before_action :require_team!

  def index
    @view_mode = params[:view] || 'lanes'
    @issues = current_team.issues.not_archived.includes(:lane, :project, :milestone, :labels, :assignee, :creator)
    @lanes = current_team.lanes.includes(:issues)

    case @view_mode
    when 'milestone'
      @milestones = current_team.milestones.includes(projects: :issues)
      @ungrouped_issues = @issues.where(milestone_id: nil, project_id: nil)
    end
  end
end
