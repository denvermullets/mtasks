class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :api_tokens, dependent: :destroy

  enum :role, { member: 0, admin: 1 }

  AVAILABLE_THEMES = %w[
    default warm-paper cool-linen phosphor-amber phosphor-green
    dusk brutalist-newsprint muted-sage deep-navy warm-dusk
    ink ocean-floor ash chalk dusk-redux
  ].freeze

  AVAILABLE_FONTS = %w[
    ibm-plex-mono jetbrains-mono fira-code suse-mono
    roboto-mono atkinson-hyperlegible-mono
    inter ibm-plex-sans space-grotesk system
  ].freeze

  SETTINGS_DEFAULTS = {
    'appearance' => {
      'theme' => 'default',
      'font' => 'inter'
    }
  }.freeze

  # Associations
  has_many :owned_workspaces, class_name: 'Workspace', foreign_key: :owner_id, dependent: :destroy
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :created_issues, class_name: 'Issue', foreign_key: :creator_id
  has_many :assigned_issues, class_name: 'Issue', foreign_key: :assignee_id
  has_many :comments, dependent: :destroy
  has_many :sent_invitations, class_name: 'TeamInvitation', foreign_key: :invited_by_id, dependent: :destroy
  has_many :notifications, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  def resolved_settings
    SETTINGS_DEFAULTS.deep_merge(settings || {})
  end

  def theme
    value = resolved_settings.dig('appearance', 'theme')
    AVAILABLE_THEMES.include?(value) ? value : 'default'
  end

  def font
    value = resolved_settings.dig('appearance', 'font')
    AVAILABLE_FONTS.include?(value) ? value : 'inter'
  end
end
