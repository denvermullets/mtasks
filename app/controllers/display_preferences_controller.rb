class DisplayPreferencesController < ApplicationController
  before_action :require_team!

  def update
    preference = UserPreference.for_user_and_team(Current.user, current_team)

    if preference.update(sanitized_params)
      # Redirect back to issues with current display options
      redirect_to team_issues_path(current_team, redirect_params),
                  notice: 'Display preferences saved as default.'
    else
      redirect_to team_issues_path(current_team),
                  alert: "Failed to save display preferences: #{preference.errors.full_messages.join(', ')}"
    end
  end

  private

  def preference_params
    params.permit(
      :view_mode,
      :group_by,
      :order_by,
      :show_sub_issues,
      :show_empty_groups,
      :completed_filter,
      visible_properties: []
    )
  end

  def sanitized_params
    prefs = preference_params
    {
      view_mode: prefs[:view_mode],
      group_by: prefs[:group_by],
      order_by: prefs[:order_by],
      show_sub_issues: prefs[:show_sub_issues] == 'true',
      show_empty_groups: prefs[:show_empty_groups] == 'true',
      completed_filter: prefs[:completed_filter].presence,
      visible_properties: prefs[:visible_properties] || []
    }
  end

  def redirect_params
    {
      view_mode: params[:view_mode],
      group_by: params[:group_by],
      order_by: params[:order_by],
      show_sub_issues: params[:show_sub_issues],
      show_empty_groups: params[:show_empty_groups],
      completed_filter: params[:completed_filter],
      visible_properties: params[:visible_properties]&.join(',')
    }
  end
end
