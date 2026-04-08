module ApplicationHelper
  def user_avatar(user, size: 'md', shape: 'circle', extra_classes: '')
    render partial: 'shared/user_avatar', locals: { user: user, size: size, shape: shape, extra_classes: extra_classes }
  end

  def format_target_date(date)
    return nil unless date

    formatted = "#{date.strftime('%b')} #{date.day.ordinalize}"
    formatted += ", #{date.year}" if date.year != Date.current.year
    formatted
  end
end
