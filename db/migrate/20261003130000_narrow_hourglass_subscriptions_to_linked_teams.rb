# Connecting Hourglass used to subscribe every team in the workspace. Keep a subscription only for
# teams that actually have a link on that integration, deactivate the rest, and narrow each callback
# token to the teams that remain. Links saved before hourglass_integration_id existed have it NULL;
# they count toward an integration when it is the only one in the team's workspace.
class NarrowHourglassSubscriptionsToLinkedTeams < ActiveRecord::Migration[8.1]
  class Integration < ActiveRecord::Base
    self.table_name = 'hourglass_integrations'
  end

  class Subscription < ActiveRecord::Base
    self.table_name = 'hourglass_channel_subscriptions'
  end

  class Link < ActiveRecord::Base
    self.table_name = 'hourglass_links'
  end

  class Team < ActiveRecord::Base
    self.table_name = 'teams'
  end

  class Token < ActiveRecord::Base
    self.table_name = 'api_tokens'
  end

  class TokenTeam < ActiveRecord::Base
    self.table_name = 'api_token_teams'
  end

  def up
    Integration.find_each { |integration| narrow(integration) }
  end

  def down
    # Which teams were fanned out is not recorded anywhere worth restoring; reconnecting re-adds teams.
  end

  private

  def narrow(integration)
    keep = linked_team_ids(integration)
    now = Time.current
    dropped = deactivate_unlinked(integration, keep, now)
    added = ensure_subscriptions(integration, keep, now)
    narrow_token(integration, keep, now)

    say "hourglass_integration #{integration.id} (server #{integration.hourglass_server_id}): " \
        "keeping teams #{keep.sort.inspect}, deactivated #{dropped.sort.inspect}, " \
        "added #{added.sort.inspect}#{', no linked teams left' if keep.empty?}"
  end

  def deactivate_unlinked(integration, keep, now)
    subs = Subscription.where(hourglass_integration_id: integration.id)
    dropped = subs.where(active: true).where.not(team_id: keep).pluck(:team_id)
    subs.where(team_id: dropped).update_all(active: false, updated_at: now)
    dropped
  end

  def linked_team_ids(integration)
    ids = Link.where(hourglass_integration_id: integration.id).distinct.pluck(:team_id)
    if Integration.where(workspace_id: integration.workspace_id).one?
      workspace_team_ids = Team.where(workspace_id: integration.workspace_id).select(:id)
      ids |= Link.where(hourglass_integration_id: nil, team_id: workspace_team_ids).distinct.pluck(:team_id)
    end
    ids
  end

  def ensure_subscriptions(integration, team_ids, now)
    existing = Subscription.where(hourglass_integration_id: integration.id, team_id: team_ids)
    existing.where(active: false).update_all(active: true, updated_at: now)
    missing = team_ids - existing.pluck(:team_id)
    missing.each do |team_id|
      Subscription.create!(
        hourglass_integration_id: integration.id, team_id: team_id, active: true,
        hourglass_server_id: integration.hourglass_server_id,
        hourglass_server_name: integration.hourglass_server_name
      )
    end
    missing
  end

  def narrow_token(integration, team_ids, now)
    return if integration.callback_api_token_id.nil?

    token = Token.find_by(id: integration.callback_api_token_id)
    return if token.nil? || token.revoked_at.present?

    token.update_columns(team_scoped: true, updated_at: now)
    TokenTeam.where(api_token_id: token.id).where.not(team_id: team_ids).delete_all
    (team_ids - TokenTeam.where(api_token_id: token.id).pluck(:team_id)).each do |team_id|
      TokenTeam.create!(api_token_id: token.id, team_id: team_id)
    end
  end
end
