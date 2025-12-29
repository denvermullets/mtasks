class MilestonesController < ApplicationController
  include TeamScoped

  before_action :set_milestone, only: %i[update destroy]

  def index
    @milestones = current_team.milestones.by_due_date
    @context = params[:context] || 'sidebar'
    @issue_id = params[:issue_id]
  end

  def create
    @milestone = current_team.milestones.build(milestone_params)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: @milestone.save ? milestone_created_stream : milestone_error_stream
      end
    end
  end

  def update
    if @milestone.update(milestone_params)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def destroy
    @milestone.destroy
    head :no_content
  end

  private

  def milestone_created_stream
    turbo_stream.append(
      'milestones_list',
      partial: 'milestones/milestone_option',
      locals: { milestone: @milestone, selected: true }
    )
  end

  def milestone_error_stream
    turbo_stream.replace(
      'milestone_form_errors',
      partial: 'shared/errors',
      locals: { errors: @milestone.errors.full_messages }
    )
  end

  def set_milestone
    @milestone = current_team.milestones.find(params[:id])
  end

  def milestone_params
    params.require(:milestone).permit(:name, :due_date, :description, :start_date)
  end
end
