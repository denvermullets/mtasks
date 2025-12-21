class IssueLabelsController < ApplicationController
  include TeamScoped

  before_action :set_issue

  def create
    label = current_team.labels.find(params[:label_id])
    issue_label = @issue.issue_labels.build(label: label)

    if issue_label.save
      render json: {
        id: issue_label.id,
        label: {
          id: label.id,
          name: label.name,
          color: label.color
        }
      }, status: :created
    else
      render json: { errors: issue_label.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    issue_label = @issue.issue_labels.find_by(label_id: params[:id])

    if issue_label
      issue_label.destroy
      head :no_content
    else
      render json: { error: 'Label not found on this issue' }, status: :not_found
    end
  end

  private

  def set_issue
    @issue = current_team.issues.find(params[:issue_id])
  end
end
