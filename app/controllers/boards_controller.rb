class BoardsController < ApplicationController
  before_action :require_team!

  def index
    @view_mode = params[:view] || 'priority' # priority or milestone
    @issues = current_team.issues.not_archived.includes(:lane, :project, :milestone, :labels, :assignee, :creator)

    case @view_mode
    when 'milestone'
      @milestones = current_team.milestones.includes(projects: :issues)
      @ungrouped_issues = @issues.where(milestone_id: nil, project_id: nil)
    when 'priority'
      @lanes = current_team.lanes.includes(:issues)
      # Group issues by priority for the priority view
      @priorities = Issue.priorities.keys.map(&:to_sym)
    else
      @lanes = current_team.lanes.includes(:issues)
    end
  end
end
