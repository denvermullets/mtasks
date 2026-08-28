# Index-only view preparation for IssuesController, alongside FormCollections (which does the
# same job for the new/edit forms). Extracted so the controller stays under Metrics/ClassLength;
# no behavior change.
module IssueIndexFilters
  extend ActiveSupport::Concern

  private

  def load_display_options
    @display_options = DisplayOptionsService.call(params, Current.user, current_team)
  end

  def load_index_filters
    @lanes = current_team.lanes.order(:position)
    @labels = current_team.labels.includes(:issue_labels)
    @projects = current_team.projects.order(:name)
    @assignees = current_team.users.order(:name)
    @creators = @assignees
  end
end
