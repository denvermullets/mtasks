# Saves the drag-and-drop layout from the Team Order settings: group order, each group's teams, and
# the order of the ungrouped owned / joined teams. Group names and collapsed state are left untouched.
class Settings::TeamOrderController < ApplicationController
  def update
    persist_layout(user_teams.map(&:id))
    @layout = current_user.sidebar_layout(user_teams)

    respond_to do |format|
      format.turbo_stream
      format.json { head :ok }
    end
  end

  private

  def persist_layout(valid_ids)
    groups = ordered_groups(valid_ids)
    grouped_ids = groups.flat_map { |group| group['team_ids'] }
    team_order = %w[owned joined].index_with { |scope| sanitize_ids(params[scope], valid_ids) - grouped_ids }

    settings = (current_user.settings || {}).merge('sidebar_groups' => groups, 'team_order' => team_order)
    current_user.update!(settings: settings)
  end

  # Reorders the stored groups to match the submitted ids and replaces their team lists; groups the
  # client left out keep their place at the end so a stale page can't drop them. A team lands in at
  # most one group.
  def ordered_groups(valid_ids)
    submitted = Array(params[:groups]).to_h { |group| [group[:id].to_s, sanitize_ids(group[:team_ids], valid_ids)] }
    claimed = []

    sort_by_submitted(current_user.sidebar_groups, submitted.keys).map do |group|
      ids = submitted.fetch(group['id'], group['team_ids']) - claimed
      claimed.concat(ids)
      group.merge('team_ids' => ids)
    end
  end

  def sort_by_submitted(groups, submitted_ids)
    groups.sort_by.with_index { |group, i| [submitted_ids.index(group['id']) || submitted_ids.size, i] }
  end

  def sanitize_ids(ids, valid_ids)
    Array(ids).map(&:to_i).select { |id| valid_ids.include?(id) }.uniq
  end
end
