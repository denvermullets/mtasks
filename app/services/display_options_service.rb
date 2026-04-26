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
      lane_ids: int_list_param(:lane_ids),
      assignee_ids: int_list_param(:assignee_ids),
      creator_ids: int_list_param(:creator_ids),
      label_ids: int_list_param(:label_ids),
      project_ids: int_list_param(:project_ids),
      priority: string_list_param(:priority)
    }
  end

  private

  def int_list_param(key)
    list = string_list_param(key)
    list&.map(&:to_i)
  end

  def string_list_param(key)
    raw = params[key]
    return nil if raw.blank?

    values = raw.to_s.split(',').map(&:strip).reject(&:blank?)
    values.presence
  end

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
