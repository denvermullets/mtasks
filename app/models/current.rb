class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user

  def user
    super || session&.user
  end
end
