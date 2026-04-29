class HourglassUserMap < ApplicationRecord
  self.table_name = 'hourglass_user_map'

  belongs_to :mtasks_user, class_name: 'User'

  validates :hourglass_user_id, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true
end
