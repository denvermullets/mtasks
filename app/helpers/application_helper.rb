module ApplicationHelper
  def user_avatar(user, size: 'md', shape: 'circle', extra_classes: '')
    render partial: 'shared/user_avatar', locals: { user: user, size: size, shape: shape, extra_classes: extra_classes }
  end
end
