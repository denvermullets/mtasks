class LabelsController < ApplicationController
  include TeamScoped

  before_action :set_label, only: %i[update destroy]

  def create
    @label = current_team.labels.build(label_params)
    @current_label_ids = [] # New labels aren't assigned to any issue yet

    if @label.save
      track_feature('label-management', 'create')
    else
      render turbo_stream: turbo_stream.append('errors', 'Error creating label'), status: :unprocessable_entity
    end
  end

  def update
    if @label.update(label_params)
      track_feature('label-management', 'update')
    else
      render turbo_stream: turbo_stream.append('errors', 'Error updating label'), status: :unprocessable_entity
    end
  end

  def destroy
    @label.destroy
    track_feature('label-management', 'delete') if @label.destroyed?
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
