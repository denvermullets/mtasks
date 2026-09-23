# Registers mtasks with the vektis-rails SDK.
#
# Each team is its own VEKTIS tenant, so nothing about the connection is global except the ingest
# endpoint (config.x.vektis.endpoint, set per environment). A team's credentials live in
# TeamVektisIntegration and decide which VEKTIS account its events are delivered to.
Vektis.configure do |c|
  c.endpoint = Rails.application.config.x.vektis.endpoint
  c.product_name = 'mtasks-rails'

  # Read the row directly rather than through Team#has_one: a settings save has to be visible to the
  # very next emit, and a memoized association on a long-lived team object would not be. Handles
  # both shapes because the emit path passes a Team and Vektis::DeliveryJob passes a bare id.
  c.credentials do |team|
    TeamVektisIntegration.find_by(team_id: team.respond_to?(:id) ? team.id : team)
  end

  # Webhook and job paths have no Current.user, so absence here is automatic — and correct.
  c.current_user_id { Current.user&.id }
end

# The registry is registered in to_prepare rather than above because EventTaxonomy is an autoloaded
# constant: referencing one while initializers run would both fail here and pin a stale copy across
# a reload. to_prepare re-runs on every reload, so editing the catalog in development takes effect
# without a restart.
#
# See app/services/event_taxonomy.rb, which follows .notes/mtasks-event-taxonomy.md.
Rails.application.config.to_prepare do
  Vektis.config.registry do |r|
    r.event_id_namespace = EventTaxonomy::EVENT_ID_NAMESPACE
    r.property_keys = EventTaxonomy::PROPERTY_KEYS
    r.features(EventTaxonomy::CATALOG)
  end
end
