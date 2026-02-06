class NotificationsController < ApplicationController
  def index
    @notifications = Current.user.notifications.recent.includes(:actor, :issue)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          'notification_list',
          partial: 'notifications/list',
          locals: { notifications: @notifications }
        )
      end
      format.html { redirect_to root_path }
    end
  end

  def mark_as_read
    @notification = Current.user.notifications.find(params[:id])
    @notification.mark_as_read!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            dom_id(@notification),
            partial: 'notifications/notification',
            locals: { notification: @notification }
          ),
          replace_all_badges
        ]
      end
      format.html { redirect_to root_path }
    end
  end

  def mark_all_as_read
    Current.user.notifications.unread.update_all(read_at: Time.current)

    respond_to do |format|
      format.turbo_stream do
        @notifications = Current.user.notifications.recent.includes(:actor, :issue)
        render turbo_stream: [
          turbo_stream.replace(
            'notification_list',
            partial: 'notifications/list',
            locals: { notifications: @notifications }
          ),
          replace_all_badges
        ]
      end
      format.html { redirect_to root_path }
    end
  end

  private

  def replace_all_badges
    count = Current.user.notifications.unread.count
    turbo_stream.replace_all(
      '.notification-badge',
      partial: 'notifications/badge',
      locals: { count: count }
    )
  end
end
