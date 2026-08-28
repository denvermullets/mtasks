class IssueLabelsController < ApplicationController
  include TeamScoped
  include FormCollections

  before_action :set_issue
  before_action :load_form_collections, only: %i[create destroy]

  def create
    label = current_team.labels.find(params[:label_id])
    issue_label = @issue.issue_labels.build(label: label)

    if issue_label.save
      track_feature('issue-label', 'apply', entity: 'issue', count: 1)
      @issue.reload
    else
      render turbo_stream: turbo_stream.append('errors', 'Error adding label'), status: :unprocessable_entity
    end
  end

  def destroy
    issue_label = @issue.issue_labels.find_by(label_id: params[:id])

    if issue_label
      issue_label.destroy
      track_feature('issue-label', 'remove', entity: 'issue', count: 1)
      @issue.reload
    else
      render turbo_stream: turbo_stream.append('errors', 'Label not found'), status: :not_found
    end
  end

  private

  def set_issue
    @issue = current_team.issues.find(params[:issue_id])
  end
end
