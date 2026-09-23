# A team's own VEKTIS tenancy: the keys and customer id its analytics are emitted under.
#
# Each team is its own VEKTIS tenant, so nothing about the connection is global except the ingest
# endpoint. config/initializers/vektis.rb points the gem's `credentials` resolver at this model,
# which is how an event finds the account it is delivered to.
#
# The keys are stored in plaintext, matching HourglassIntegration#api_token — the only existing
# precedent in this app for an inbound third-party credential.
class TeamVektisIntegration < ApplicationRecord
  # The browser SDK is handed this key in the page, so a full-scope key here would leak to every
  # visitor. Vektis::Helper refuses to render a key without this prefix; validating it as well means
  # the mistake surfaces on the form instead of silently disabling analytics. The prefix itself is
  # the vendor's key format, so it comes from the gem rather than being restated here.
  PUBLISHABLE_KEY_PREFIX = Vektis::Helper::PUBLISHABLE_KEY_PREFIX

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
    validates :customer_id, presence: true, length: { maximum: Vektis::Schema::MAX_FIELD_LENGTH }
  end

  scope :enabled, -> { where(enabled: true) }
end
