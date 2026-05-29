class HourglassLinkReadState < ApplicationRecord
  belongs_to :user
  belongs_to :hourglass_link

  validates :last_read_at, presence: true
  validates :user_id, uniqueness: { scope: :hourglass_link_id }

  def self.touch_for(user:, hourglass_link:)
    find_or_initialize_by(user: user, hourglass_link: hourglass_link)
      .update!(last_read_at: Time.current)
  end
end
