class HourglassIntegration < ApplicationRecord
  # Inbound webhooks are addressed by public_id (/webhooks/hourglass/:public_id), so several servers
  # in one workspace each verify against their own secret. Which teams actually use the integration
  # is decided by its active subscriptions, and those may only name teams in this workspace.
  belongs_to :workspace
  belongs_to :connected_by_user, class_name: 'User', optional: true
  belongs_to :callback_api_token, class_name: 'ApiToken', optional: true
  has_many :hourglass_channel_subscriptions, dependent: :destroy
  has_many :active_subscriptions, -> { active }, class_name: 'HourglassChannelSubscription', inverse_of: false
  has_many :subscribed_teams, through: :active_subscriptions, source: :team
  has_many :hourglass_links, dependent: :nullify

  validates :hourglass_server_id, presence: true
  validates :base_url, presence: true
  validates :hourglass_server_id, uniqueness: { scope: :workspace_id }

  scope :active, -> { where(active: true) }

  def live_callback_token
    callback_api_token unless callback_api_token.nil? || callback_api_token.revoked?
  end

  # The callback token may reach exactly the teams that are actively subscribed, never more.
  def sync_callback_token_scope!
    live_callback_token&.scope_to_teams!(active_subscriptions.pluck(:team_id))
  end
end
