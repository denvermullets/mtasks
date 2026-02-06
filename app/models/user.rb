class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { member: 0, admin: 1 }

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
end
