class RoadmapsController < ApplicationController
  include TeamScoped

  before_action :require_team!

  def show
    scope = current_team.projects.includes(:lead, :team, :labels)
    @lanes = Project::ROADMAP_COMMITMENTS.index_with do |commitment|
      scope.in_commitment(commitment)
    end
    @projects_off_roadmap = scope.where(roadmap_commitment: nil).order(:name)
  end
end
