class NotificationsController < ApplicationController
  def index
    @notifications = Current.user.notifications.recent.includes(:actor, :issue)
    @unread_count = Current.user.notifications.unread.count

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
    @unread_count = Current.user.notifications.unread.count

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            dom_id(@notification),
            partial: 'notifications/notification',
            locals: { notification: @notification }
          ),
          turbo_stream.replace(
            'notification_badge',
            partial: 'notifications/badge',
            locals: { count: @unread_count }
          )
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
          turbo_stream.replace(
            'notification_badge',
            partial: 'notifications/badge',
            locals: { count: 0 }
          )
        ]
      end
      format.html { redirect_to root_path }
    end
  end
end
