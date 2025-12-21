class LabelsController < ApplicationController
  include TeamScoped

  before_action :set_label, only: %i[update destroy]

  def index
    labels = current_team.labels.includes(:issue_labels)

    # Calculate usage count for each label
    labels_with_usage = labels.map do |label|
      {
        id: label.id,
        name: label.name,
        color: label.color,
        usage_count: label.issue_labels.count
      }
    end

    # Sort by usage count descending
    sorted_labels = labels_with_usage.sort_by { |l| -l[:usage_count] }

    # Split into frequently used (top 5) and all labels
    frequently_used = sorted_labels.first(5).select { |l| l[:usage_count].positive? }
    all_labels = sorted_labels

    render json: {
      frequently_used: frequently_used,
      all_labels: all_labels
    }
  end

  def create
    label = current_team.labels.build(label_params)

    if label.save
      render json: {
        id: label.id,
        name: label.name,
        color: label.color
      }, status: :created
    else
      render json: { errors: label.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @label.update(label_params)
      render json: {
        id: @label.id,
        name: @label.name,
        color: @label.color
      }
    else
      render json: { errors: @label.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @label.destroy
    head :no_content
  end

  private

  def set_label
    @label = current_team.labels.find(params[:id])
  end

  def label_params
    params.require(:label).permit(:name, :color)
  end
end
