# Team-admin screen for connecting a team to its own VEKTIS account.
#
# Team-scoped rather than workspace-scoped, unlike Settings::HourglassIntegrationsController: the
# keys entered here identify a VEKTIS tenant, and each team is one. Authorization is admin-level
# via TeamScoped#require_team_admin!, which is stricter than the membership-level check the
# Hourglass screen rolls itself — these are credentials, not a channel mapping.
class Settings::VektisIntegrationsController < ApplicationController
  before_action :set_team
  before_action :authorize_team_admin!

  def show
    @integration = integration
  end

  def update
    @integration = integration
    was_enabled = @integration.enabled?
    @integration.assign_attributes(integration_params)
    stamp_connection(was_enabled)

    if @integration.save
      track_connection(was_enabled)
      redirect_to team_settings_vektis_integration_path(@team), notice: 'Analytics settings saved'
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    # Emitted before the destroy, not after: the event is delivered under this team's own key, and
    # once the record is gone Vektis.for(team) resolves to NullConfig and the disconnect would be
    # the one action the team could never see in its own analytics.
    track_integration('vektis-integration', 'unlink', provider: 'vektis') if integration.enabled?
    integration.destroy

    redirect_to team_settings_vektis_integration_path(@team), notice: 'Analytics disconnected'
  end

  private

  def integration
    @integration ||= TeamVektisIntegration.find_or_initialize_by(team: @team)
  end

  # The team being configured, which is also current_team on this route — stated explicitly so an
  # event can never be filed under a stale session team.
  def tracked_team
    @team
  end

  def set_team
    @team = Team.find(params[:team_id])
    authorize_team_access!(@team)
  end

  def authorize_team_admin!
    require_team_admin!(@team)
  end

  # The server key is write-only: the form submits it blank when the admin is editing something
  # else, and a blank must not wipe a stored key. The publishable key is rendered back (it is
  # public by design), so it has no such carve-out.
  def integration_params
    permitted = params.require(:team_vektis_integration)
                      .permit(:enabled, :publishable_key, :server_key, :customer_id)
    permitted.delete(:server_key) if permitted[:server_key].blank?
    permitted
  end

  def stamp_connection(was_enabled)
    return if was_enabled || !@integration.enabled?

    @integration.connected_by_user = current_user
    @integration.connected_at = Time.current
  end

  # Only the off -> on transition is a `link`. Saving an already-connected integration is an edit,
  # and counting it as a fresh connection would inflate the one number this event exists to report.
  def track_connection(was_enabled)
    return if was_enabled || !@integration.enabled?

    track_integration('vektis-integration', 'link', provider: 'vektis')
  end
end
