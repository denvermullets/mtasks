class RoadmapsController < ApplicationController
  include TeamScoped

  before_action :require_team!

  def show
    scope = current_team.projects.includes(:lead, :team, :labels)
    @lanes = Project::ROADMAP_COMMITMENTS.index_with { |commitment| scope.in_commitment(commitment) }
    @projects_off_roadmap = scope.where(roadmap_commitment: nil).order(:name)
    @status_counts = status_counts(@lanes.values.flatten)
  end

  private

  def status_counts(projects)
    {
      behind: projects.count(&:behind_schedule?),
      in_progress: projects.count { |p| !p.behind_schedule? && p.status == 'started' },
      planned: projects.count { |p| !p.behind_schedule? && !%w[started completed cancelled].include?(p.status) }
    }
  end
end
