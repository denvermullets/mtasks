class Team < ApplicationRecord
  # Associations
  belongs_to :workspace
  belongs_to :owner, class_name: 'User'
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships
  has_many :lanes, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :issues, dependent: :destroy
  has_many :labels, dependent: :destroy
  has_many :team_invitations, dependent: :destroy
  has_many :github_repository_subscriptions, dependent: :destroy
  has_many :github_installations, through: :workspace
  has_many :hourglass_channel_subscriptions, dependent: :destroy
  has_many :hourglass_links, dependent: :destroy
  has_many :decisions, dependent: :destroy
  # Vektis.for reads this table directly rather than through the association: a settings save must
  # be visible to the very next emit, and a memoized has_one on a long-lived team object would not
  # be. Declared here so destroying a team takes its analytics credentials with it.
  has_one :vektis_integration, class_name: 'TeamVektisIntegration', dependent: :destroy

  # Scopes
  scope :archived, -> { where.not(archived_at: nil) }
  scope :not_archived, -> { where(archived_at: nil) }

  # Validations
  validates :name, presence: true
  validates :identifier, presence: true, uniqueness: true, length: { in: 3..4 },
                         format: { with: /\A[A-Z0-9]+\z/, message: 'must be 3-4 uppercase letters or numbers' }

  # Callbacks
  before_validation :upcase_identifier
  before_validation :default_owner_to_workspace_owner
  after_create :create_default_lanes

  # Generate next issue number for this team
  def next_issue_number
    increment!(:issue_counter)
    issue_counter
  end

  def archive!
    transaction do
      update!(archived_at: Time.current)
      issues.not_archived.update_all(archived_at: Time.current)
    end
  end

  def owner?(user)
    user && owner_id == user.id
  end

  def admin?(user)
    return false unless user
    return true if owner?(user)

    team_memberships.where(user_id: user.id, role: TeamMembership.roles[:admin]).exists?
  end

  private

  def upcase_identifier
    self.identifier = identifier&.upcase
  end

  def default_owner_to_workspace_owner
    self.owner ||= workspace&.owner
  end

  def create_default_lanes
    default_lanes = [
      { name: 'Backlog', position: 0, color: '#94a3b8' },
      { name: 'In Progress', position: 1, color: '#3b82f6' },
      { name: 'Done', position: 2, color: '#22c55e' },
      { name: 'Cancelled', position: 3, color: '#ef4444' }
    ]

    default_lanes.each do |lane_attrs|
      lanes.create!(lane_attrs)
    end
  end
end
