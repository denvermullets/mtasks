# Named, collapsible groups of teams in the user's sidebar, stored in users.settings['sidebar_groups'].
# Teams are moved between groups from the Team Order settings (Settings::TeamOrderController).
class Settings::SidebarGroupsController < ApplicationController
  def create
    name = group_name
    return redirect_back_to_settings(alert: 'Group name is required.') if name.blank?

    group = { 'id' => SecureRandom.hex(4), 'name' => name, 'team_ids' => [], 'collapsed' => false }
    save_groups(current_user.sidebar_groups << group)
    redirect_back_to_settings(notice: 'Group created')
  end

  # Renames from the settings form, or records the collapsed state from the sidebar chevron (JSON).
  def update
    groups = current_user.sidebar_groups
    group = groups.find { |g| g['id'] == params[:id] }
    return head :not_found unless group
    return redirect_back_to_settings(alert: 'Group name is required.') if params.key?(:name) && group_name.blank?

    apply_changes(group)
    save_groups(groups)

    respond_to do |format|
      format.html { redirect_back_to_settings(notice: 'Group renamed') }
      format.json { head :ok }
    end
  end

  # Deleting a group returns its teams to their owned / joined sections.
  def destroy
    save_groups(current_user.sidebar_groups.reject { |g| g['id'] == params[:id] })
    redirect_back_to_settings(notice: 'Group deleted')
  end

  private

  def apply_changes(group)
    group['name'] = group_name if params.key?(:name)
    group['collapsed'] = ActiveModel::Type::Boolean.new.cast(params[:collapsed]) if params.key?(:collapsed)
  end

  def group_name
    params[:name].to_s.strip.first(User::SIDEBAR_GROUP_NAME_LIMIT)
  end

  def save_groups(groups)
    current_user.update!(settings: (current_user.settings || {}).merge('sidebar_groups' => groups))
  end

  def redirect_back_to_settings(**flash)
    redirect_to settings_path(section: 'team_order'), status: :see_other, **flash
  end
end
