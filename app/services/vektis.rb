# The VEKTIS analytics namespace and its one entry point.
#
# This used to be an initializer holding five ENV readers, on the premise that mtasks was a single
# VEKTIS tenant. Each team is now its own tenant, so there is no app-wide "is analytics on" — only
# "is analytics on for this team", and every emit path has to say which team it means.
#
# Declared here rather than in config/initializers so the constant is Zeitwerk-managed and
# reloadable like the rest of app/services/vektis.
module Vektis
  class << self
    # Always returns a config — NullConfig when the team is absent, has never connected, or has
    # turned tracking off. Callers branch on `enabled?`, never on nil.
    def for(team)
      return NullConfig.new if team.blank?

      record = TeamVektisIntegration.find_by(team_id: team.respond_to?(:id) ? team.id : team)
      record ? Config.new(record) : NullConfig.new
    end

    # One ingest deployment per environment, not per tenant — teams supply credentials, not a
    # destination. Set in config/environments/*.rb.
    def endpoint
      Rails.application.config.x.vektis.endpoint
    end
  end
end
