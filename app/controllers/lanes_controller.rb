class LanesController < ApplicationController
  include TeamScoped
  include LanesRendering

  before_action :require_team!
  before_action :set_lane, only: %i[update destroy]
  before_action :authorize_team_membership!

  # POST /teams/:team_id/lanes
  def create
    @lane = current_team.lanes.build(lane_params)
    @lane.position = current_team.lanes.maximum(:position).to_i + 1 if @lane.position.blank?
    if @lane.save
      track_feature('lane-management', 'create', to_position: @lane.position)
      render_lane_created
    else
      render_lane_create_error
    end
  end

  # PATCH /teams/:team_id/lanes/:id
  def update
    if position_changed?
      from_position = @lane.position
      update_lane_positions
      track_lane_reorder(from_position)
    elsif @lane.update(lane_params)
      track_feature('lane-management', 'update')
    end

    respond_to do |format|
      format.turbo_stream { render_lane_update }
      format.html { redirect_to edit_team_path(current_team) }
    end
  end

  # DELETE /teams/:team_id/lanes/:id
  def destroy
    return render_last_lane_error if last_lane?
    return render_reassignment_required if requires_reassignment?

    reassign_issues_if_needed
    from_position = @lane.position
    @lane.destroy
    track_feature('lane-management', 'delete', from_position: from_position) if @lane.destroyed?

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("lane_#{@lane.id}")
      end
      format.html { redirect_to edit_team_path(current_team) }
    end
  end

  private

  # Reordering is a lane-management update. Lane *names* are user-authored free text and may
  # never ship (taxonomy §6); position is the registered stand-in.
  def track_lane_reorder(from_position)
    to_position = @lane.position
    track_feature('lane-management', 'update', from_position: from_position, to_position: to_position,
                                               direction: to_position > from_position ? 'forward' : 'backward')
  end

  def set_lane
    @lane = current_team.lanes.find(params[:id])
  end

  def lane_params
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

  def reassign_issues_if_needed
    return unless @lane.issues.any?

    target_lane = current_team.lanes.find(params[:target_lane_id])
    @lane.issues.update_all(lane_id: target_lane.id)
  end

  def position_changed?
    lane_params[:position].present? && @lane.position != lane_params[:position].to_i
  end

  def update_lane_positions
    new_position = lane_params[:position].to_i
    old_position = @lane.position

    # Find the lane at the target position
    lane_at_target = current_team.lanes.find_by(position: new_position)

    # Swap positions and re-normalize
    Lane.transaction do
      lane_at_target&.update_column(:position, old_position)
      @lane.update_column(:position, new_position)

      # Re-normalize all positions to be sequential
      current_team.lanes.order(:position).each_with_index do |lane, index|
        lane.update_column(:position, index) if lane.position != index
      end
    end
  end
end
