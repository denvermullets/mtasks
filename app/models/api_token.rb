class ApiToken < ApplicationRecord
  AVAILABLE_SCOPES = %w[read write].freeze

  belongs_to :user
  belongs_to :team, optional: true

  scope :active, -> { where(revoked_at: nil) }

  validates :scopes, presence: true
  validate :scopes_must_be_subset

  attr_accessor :raw_token

  def self.generate_for(user, name: 'API Token', team: nil, scopes: AVAILABLE_SCOPES)
    raw = SecureRandom.base58(36)
    token = user.api_tokens.create!(
      token_digest: Digest::SHA256.hexdigest(raw),
      name: name,
      team: team,
      scopes: Array(scopes).map(&:to_s)
    )
    token.raw_token = raw
    token
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    digest = Digest::SHA256.hexdigest(raw_token)
    active.find_by(token_digest: digest)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def can_read?
    scopes.include?('read')
  end

  def can_write?
    scopes.include?('write')
  end

  def scoped_to_team?
    team_id.present?
  end

  private

  def scopes_must_be_subset
    return if scopes.is_a?(Array) && (scopes - AVAILABLE_SCOPES).empty?

    errors.add(:scopes, "must be a subset of #{AVAILABLE_SCOPES.join(', ')}")
  end
end
