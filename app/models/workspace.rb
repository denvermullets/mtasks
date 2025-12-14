class Workspace < ApplicationRecord
  # Associations
  belongs_to :owner, class_name: "User"
  has_many :teams, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :identifier, presence: true, uniqueness: true, length: { is: 3 }, format: { with: /\A[A-Z]+\z/, message: "must be 3 uppercase letters" }

  before_validation :upcase_identifier

  private

  def upcase_identifier
    self.identifier = identifier&.upcase
  end
end
