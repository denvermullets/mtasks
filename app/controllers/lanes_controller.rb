class LanesController < ApplicationController
  include TeamScoped

  before_action :require_team!
  before_action :set_lane, only: %i[update destroy]
  before_action :authorize_team_membership!

  # POST /teams/:team_id/lanes
  def create
    @lane = current_team.lanes.build(lane_params)
    @lane.save ? render_lane_created : render_lane_create_error
  end

  # PATCH /teams/:team_id/lanes/:id
  def update
    @lane.update(lane_params)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("lane_#{@lane.id}",
                                                  partial: 'lanes/lane_row', locals: { lane: @lane })
      end
      format.html { redirect_to edit_team_path(current_team) }
    end
  end

  # DELETE /teams/:team_id/lanes/:id
  def destroy
    return render_last_lane_error if last_lane?
    return render_reassignment_required if requires_reassignment?

    reassign_issues_if_needed
    @lane.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("lane_#{@lane.id}")
      end
      format.html { redirect_to edit_team_path(current_team) }
    end
  end

  private

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

  def render_last_lane_error
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          'flash_messages',
          partial: 'shared/flash',
          locals: { message: 'Cannot delete the last lane', type: 'alert' }
        ), status: :unprocessable_entity
      end
      format.html { redirect_to edit_team_path(current_team), alert: 'Cannot delete the last lane' }
    end
  end

  def render_reassignment_required
    @available_lanes = current_team.lanes.where.not(id: @lane.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          'modals',
          partial: 'lanes/reassignment_modal',
          locals: { lane: @lane, available_lanes: @available_lanes }
        )
      end
      format.html do
        redirect_to edit_team_path(current_team), alert: 'This lane has issues. Please reassign them first.'
      end
    end
  end

  def reassign_issues_if_needed
    return unless @lane.issues.any?

    target_lane = current_team.lanes.find(params[:target_lane_id])
    @lane.issues.update_all(lane_id: target_lane.id)
  end

  def render_lane_created
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append('lanes_list', partial: 'lanes/lane_row', locals: { lane: @lane }),
          turbo_stream.update('add_lane_form', partial: 'lanes/add_lane_form_content')
        ]
      end
      format.html { redirect_to edit_team_path(current_team) }
    end
  end

  def render_lane_create_error
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update('add_lane_form', partial: 'lanes/add_lane_form_content',
                                                                  locals: { lane: @lane })
      end
      format.html { redirect_to edit_team_path(current_team), alert: @lane.errors.full_messages.join(', ') }
    end
  end
end
