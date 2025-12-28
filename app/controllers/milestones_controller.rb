class MilestonesController < ApplicationController
  include TeamScoped

  before_action :set_milestone, only: %i[update destroy]

  def index
    milestones = current_team.milestones.by_due_date

    milestones_data = milestones.map do |milestone|
      {
        id: milestone.id,
        name: milestone.name,
        due_date: milestone.due_date,
        formatted_due_date: milestone.formatted_due_date,
        status_color: milestone.status_color,
        issue_count: milestone.issue_count
      }
    end

    render json: { milestones: milestones_data }
  end

  def create
    milestone = current_team.milestones.build(milestone_params)

    if milestone.save
      render json: {
        id: milestone.id,
        name: milestone.name,
        due_date: milestone.due_date,
        formatted_due_date: milestone.formatted_due_date,
        status_color: milestone.status_color
      }, status: :created
    else
      render json: { errors: milestone.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @milestone.update(milestone_params)
      render json: {
        id: @milestone.id,
        name: @milestone.name,
        due_date: @milestone.due_date,
        formatted_due_date: @milestone.formatted_due_date,
        status_color: @milestone.status_color
      }
    else
      render json: { errors: @milestone.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @milestone.destroy
    head :no_content
  end

  private

  def set_milestone
    @milestone = current_team.milestones.find(params[:id])
  end

  def milestone_params
    params.require(:milestone).permit(:name, :due_date, :description, :start_date)
  end
end
