class DisplayOptionsService < Service
  attr_reader :params, :user, :team, :saved_prefs

  def initialize(params, user, team)
    @params = params
    @user = user
    @team = team
    @saved_prefs = UserPreference.for_user_and_team(user, team)
  end

  def call
    {
      view_mode: param_or_pref(:view_mode),
      group_by: param_or_pref(:group_by),
      sub_group_by: param_or_pref(:sub_group_by, 'none'),
      order_by: param_or_pref(:order_by),
      show_sub_issues: bool_param(:show_sub_issues),
      show_empty_groups: bool_param(:show_empty_groups),
      show_empty_rows: bool_param(:show_empty_rows),
      completed_filter: param_or_pref(:completed_filter),
      visible_properties: visible_properties,
      assignee_id: params[:assignee_id]
    }
  end

  private

  def param_or_pref(key, default = nil)
    params[key] || saved_prefs.public_send(key) || default
  end

  def bool_param(key)
    return saved_prefs.public_send(key) if params[key].nil?

    %w[true 1].include?(params[key].to_s)
  end

  def visible_properties
    params[:visible_properties]&.split(',') || saved_prefs.visible_properties_array
  end
end
