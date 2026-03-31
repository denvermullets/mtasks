class ApiToken < ApplicationRecord
  belongs_to :user

  scope :active, -> { where(revoked_at: nil) }

  attr_accessor :raw_token

  def self.generate_for(user)
    user.api_tokens.active.update_all(revoked_at: Time.current)

    raw = SecureRandom.base58(36)
    token = user.api_tokens.create!(
      token_digest: Digest::SHA256.hexdigest(raw),
      name: 'API Token'
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
end
