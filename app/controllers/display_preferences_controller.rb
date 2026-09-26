class DisplayPreferencesController < ApplicationController
  before_action :require_team!

  def update
    preference = UserPreference.for_user_and_team(Current.user, current_team)
    return update_show_dependencies(preference) if request.format.json?

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

  # The board's Dependencies toggle saves on click, so it only touches its own column rather
  # than resetting every other display default the way the full form submit does.
  def update_show_dependencies(preference)
    if preference.update(show_dependencies: params[:show_dependencies].to_s == 'true')
      head :no_content
    else
      render json: { errors: preference.errors.full_messages }, status: :unprocessable_content
    end
  end

  def preference_params
    params.permit(
      :view_mode,
      :group_by,
      :sub_group_by,
      :order_by,
      :show_sub_issues,
      :show_empty_groups,
      :show_empty_rows,
      :show_dependencies,
      :completed_filter,
      visible_properties: []
    )
  end

  def sanitized_params
    prefs = preference_params
    {
      view_mode: prefs[:view_mode],
      group_by: prefs[:group_by],
      sub_group_by: prefs[:sub_group_by],
      order_by: prefs[:order_by],
      show_sub_issues: prefs[:show_sub_issues] == 'true',
      show_empty_groups: prefs[:show_empty_groups] == 'true',
      show_empty_rows: prefs[:show_empty_rows] == 'true',
      show_dependencies: prefs[:show_dependencies] == 'true',
      completed_filter: prefs[:completed_filter].presence,
      visible_properties: prefs[:visible_properties] || []
    }
  end

  def redirect_params
    {
      view_mode: params[:view_mode],
      group_by: params[:group_by],
      sub_group_by: params[:sub_group_by],
      order_by: params[:order_by],
      show_sub_issues: params[:show_sub_issues],
      show_empty_groups: params[:show_empty_groups],
      show_empty_rows: params[:show_empty_rows],
      show_dependencies: params[:show_dependencies],
      completed_filter: params[:completed_filter],
      visible_properties: params[:visible_properties]&.join(',')
    }
  end
end
