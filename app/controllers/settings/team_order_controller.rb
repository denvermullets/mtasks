class Settings::TeamOrderController < ApplicationController
  def show
    owned, joined = user_teams.partition { |t| team_owner?(t) }
    @owned_teams = current_user.order_teams(owned, :owned)
    @joined_teams = current_user.order_teams(joined, :joined)
  end

  def update
    scope = params[:scope].to_s
    return head :unprocessable_entity unless %w[owned joined].include?(scope)

    persist_order(scope, sanitized_ids)

    @scope = scope
    @teams = ordered_teams(scope)

    respond_to do |format|
      format.turbo_stream
      format.json { head :ok }
    end
  end

  private

  def sanitized_ids
    valid_ids = user_teams.pluck(:id)
    Array(params[:ids]).map(&:to_i).select { |id| valid_ids.include?(id) }
  end

  def persist_order(scope, ordered)
    current_settings = current_user.settings || {}
    team_order = current_settings.fetch('team_order', {})
    team_order[scope] = ordered
    current_user.update!(settings: current_settings.merge('team_order' => team_order))
  end

  def ordered_teams(scope)
    owned, joined = user_teams.partition { |t| team_owner?(t) }
    current_user.order_teams(scope == 'owned' ? owned : joined, scope)
  end
end
