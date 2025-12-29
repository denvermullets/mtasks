module FormCollections
  extend ActiveSupport::Concern

  private

  def load_form_collections
    @lanes = current_team.lanes
    @team_members = current_team.users
    @labels = current_team.labels
    @projects = current_team.projects
    @milestones = current_team.milestones
    @visible_properties = UserPreference.for_user_and_team(Current.user, current_team).visible_properties_array
  end
end
