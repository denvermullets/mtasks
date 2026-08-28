# A team's own VEKTIS tenancy: the keys and customer id its analytics are emitted under.
#
# This replaces config/initializers/vektis.rb, which held one set of ENV-driven values for the
# whole app on the premise that "mtasks is one VEKTIS tenant". Each team is now its own tenant,
# so nothing about the connection is global any more except the ingest endpoint.
#
# The keys are stored in plaintext, matching HourglassIntegration#api_token — the only existing
# precedent in this app for an inbound third-party credential.
class TeamVektisIntegration < ApplicationRecord
  # The browser SDK is handed this key in the page, so a full-scope key here would leak to every
  # visitor. VektisHelper refuses to render a key without this prefix; validating it as well means
  # the mistake surfaces on the form instead of silently disabling analytics.
  PUBLISHABLE_KEY_PREFIX = 'vk_pub_'.freeze

  belongs_to :team
  belongs_to :connected_by_user, class_name: 'User', optional: true

  # Only enforced once the team turns tracking on, so a half-filled row can still be saved.
  with_options if: :enabled? do
    validates :publishable_key, presence: true,
                                format: {
                                  with: /\A#{PUBLISHABLE_KEY_PREFIX}/,
                                  message: "must be a publishable (#{PUBLISHABLE_KEY_PREFIX}*) key"
                                }
    validates :server_key, presence: true
    validates :customer_id, presence: true, length: { maximum: Vektis::Taxonomy::MAX_FIELD_LENGTH }
  end

  scope :enabled, -> { where(enabled: true) }
end
