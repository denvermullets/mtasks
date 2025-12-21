module LanesRendering
  extend ActiveSupport::Concern

  private

  def render_lane_update
    if lane_params[:position].present?
      current_team.lanes.reload
      render turbo_stream: turbo_stream.update('lanes_list', partial: 'lanes/lanes_list',
                                                             locals: { lanes: current_team.lanes })
    else
      render turbo_stream: turbo_stream.replace("lane_#{@lane.id}", partial: 'lanes/lane_row',
                                                                    locals: { lane: @lane })
    end
  end

  def render_last_lane_error
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          'flash_messages', partial: 'shared/flash', locals: { message: 'Cannot delete the last lane', type: 'alert' }
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

  def render_lane_created
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append('lanes_list', partial: 'lanes/lane_row', locals: { lane: @lane }),
          turbo_stream.update('add_lane_form', partial: 'lanes/add_lane_form_content', locals: { lane: Lane.new })
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
