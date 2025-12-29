class LabelsController < ApplicationController
  include TeamScoped

  before_action :set_label, only: %i[update destroy]

  def create
    @label = current_team.labels.build(label_params)
    @current_label_ids = [] # New labels aren't assigned to any issue yet

    if @label.save
      # Turbo Stream will append the new label to all label pickers
    else
      render turbo_stream: turbo_stream.append('errors', 'Error creating label'), status: :unprocessable_entity
    end
  end

  def update
    if @label.update(label_params)
      # Turbo Stream will update all instances of this label
    else
      render turbo_stream: turbo_stream.append('errors', 'Error updating label'), status: :unprocessable_entity
    end
  end

  def destroy
    @label.destroy
    # Turbo Stream will remove all instances of this label
  end

  private

  def set_label
    @label = current_team.labels.find(params[:id])
  end

  def label_params
    params.require(:label).permit(:name, :color)
  end
end
