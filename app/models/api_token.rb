class ApiToken < ApplicationRecord
  AVAILABLE_SCOPES = %w[read write].freeze

  # Team scope lives in api_token_teams now; the old single-team column was backfilled into it and
  # is dropped in a follow-up migration.
  self.ignored_columns += %w[team_id]

  belongs_to :user
  # Only meaningful on one-time Hourglass bootstrap tokens: it names the workspace the handshake
  # creates the integration in. It is not an access scope; team access is decided by the team set.
  belongs_to :workspace, optional: true
  has_many :api_token_teams, dependent: :delete_all
  has_many :scoped_teams, through: :api_token_teams, source: :team

  scope :active, -> { where(revoked_at: nil) }

  validates :scopes, presence: true
  validate :scopes_must_be_subset

  attr_accessor :raw_token

  # teams: nil leaves the token unscoped (every team the user belongs to); any collection, even an
  # empty one, scopes it to exactly those teams.
  def self.generate_for(user, name: 'API Token', teams: nil, scopes: AVAILABLE_SCOPES)
    raw = SecureRandom.base58(36)
    token = transaction do
      user.api_tokens.create!(
        token_digest: Digest::SHA256.hexdigest(raw),
        name: name,
        scopes: Array(scopes).map(&:to_s)
      ).tap { |t| t.scope_to_teams!(teams) unless teams.nil? }
    end
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

  def allows_team?(team)
    return true unless team_scoped?

    api_token_teams.exists?(team_id: team.id)
  end

  # Narrows a team relation to what this token may reach; unscoped tokens pass it through.
  def filter_teams(teams)
    return teams unless team_scoped?

    teams.where(id: api_token_teams.select(:team_id))
  end

  # Replaces the team set in place. The digest is untouched, so whoever holds the raw token keeps
  # the same credential while its reach changes.
  def scope_to_teams!(teams)
    ids = team_ids_for(teams)
    transaction do
      update!(team_scoped: true)
      api_token_teams.where.not(team_id: ids).delete_all
      (ids - api_token_teams.pluck(:team_id)).each { |id| api_token_teams.create!(team_id: id) }
    end
    api_token_teams.reset
    scoped_teams.reset
  end

  def add_team!(team)
    scope_to_teams!(scoped_team_ids | [team.id])
  end

  def remove_team!(team)
    scope_to_teams!(scoped_team_ids - [team.id])
  end

  def scoped_team_ids
    api_token_teams.pluck(:team_id)
  end

  private

  def team_ids_for(teams)
    Array(teams).map { |t| t.is_a?(Team) ? t.id : Integer(t) }.uniq
  end

  def scopes_must_be_subset
    return if scopes.is_a?(Array) && (scopes - AVAILABLE_SCOPES).empty?

    errors.add(:scopes, "must be a subset of #{AVAILABLE_SCOPES.join(', ')}")
  end
end
