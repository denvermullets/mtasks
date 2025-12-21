class LanesController < ApplicationController
  include TeamScoped

  before_action :require_team!
  before_action :set_lane, only: %i[update destroy]
  before_action :authorize_team_membership!

  # POST /teams/:team_id/lanes
  def create
    @lane = current_team.lanes.build(lane_create_params)

    if @lane.save
      render json: {
        id: @lane.id,
        name: @lane.name,
        color: @lane.color,
        position: @lane.position
      }, status: :created
    else
      render json: { errors: @lane.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # PATCH /teams/:team_id/lanes/:id
  def update
    if @lane.update(lane_params)
      render json: {
        id: @lane.id,
        name: @lane.name,
        color: @lane.color,
        position: @lane.position
      }
    else
      render json: { errors: @lane.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /teams/:team_id/lanes/:id
  def destroy
    return render_last_lane_error if last_lane?
    return render_reassignment_required if requires_reassignment?

    reassign_issues_if_needed
    @lane.destroy
    head :no_content
  end

  private

  def set_lane
    @lane = current_team.lanes.find(params[:id])
  end

  def lane_params
    params.require(:lane).permit(:name, :color, :position)
  end

  def lane_create_params
    params.require(:lane).permit(:name, :color, :position)
  end

  def authorize_team_membership!
    return if current_team.users.include?(Current.user)

    render json: { error: "You don't have permission to modify this team" },
           status: :forbidden
  end

  def last_lane?
    current_team.lanes.count <= 1
  end

  def requires_reassignment?
    @lane.issues.any? && params[:target_lane_id].blank?
  end

  def render_last_lane_error
    render json: { error: 'Cannot delete the last lane' },
           status: :unprocessable_entity
  end

  def render_reassignment_required
    render json: {
      error: 'Lane has issues',
      requires_reassignment: true,
      issue_count: @lane.issues.count,
      available_lanes: available_lanes_for_reassignment
    }, status: :unprocessable_entity
  end

  def available_lanes_for_reassignment
    current_team.lanes.where.not(id: @lane.id).map do |lane|
      { id: lane.id, name: lane.name, color: lane.color }
    end
  end

  def reassign_issues_if_needed
    return unless @lane.issues.any?

    target_lane = current_team.lanes.find(params[:target_lane_id])
    @lane.issues.update_all(lane_id: target_lane.id)
  end
end
