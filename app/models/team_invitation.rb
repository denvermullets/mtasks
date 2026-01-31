class TeamInvitation < ApplicationRecord
  belongs_to :team
  belongs_to :invited_by, class_name: 'User'

  enum :status, { pending: 0, accepted: 1, declined: 2 }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, uniqueness: true
  validates :email, uniqueness: { scope: %i[team_id status], conditions: -> { where(status: :pending) },
                                  message: 'already has a pending invitation for this team' }
  validate :cannot_invite_self
  validate :not_already_a_member

  before_create :generate_token

  scope :pending, -> { where(status: :pending) }
  scope :accepted, -> { where(status: :accepted) }
  scope :declined, -> { where(status: :declined) }

  normalizes :email, with: ->(e) { e.strip.downcase }

  def accept!(user)
    transaction do
      team.team_memberships.find_or_create_by!(user: user)
      update_columns(status: TeamInvitation.statuses[:accepted], accepted_at: Time.current)
    end
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  def cannot_invite_self
    return unless invited_by && email == invited_by.email

    errors.add(:email, "you can't invite yourself")
  end

  def not_already_a_member
    return unless team

    user = User.find_by(email: email)
    return unless user && team.users.include?(user)

    errors.add(:email, 'is already a member of this team')
  end
end
