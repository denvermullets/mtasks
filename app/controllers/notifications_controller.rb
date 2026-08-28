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
    # mark_as_read! no-ops when the notification was already read, so this counts gestures that
    # actually changed something. Attributed to the notification's own issue team rather than
    # current_team: the drawer is reachable from any page, including one for another team.
    track_feature('notification', 'read', team: @notification.issue.team) if @notification.saved_change_to_read_at?

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            # dom_id is a view helper, not a controller method — this path raised NoMethodError
            # for every turbo_stream "mark as read" click. ProjectsController already qualifies
            # it the same way.
            ActionView::RecordIdentifier.dom_id(@notification),
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
    marked = Current.user.notifications.unread.update_all(read_at: Time.current)
    # Deliberately one event with a count, and deliberately attributed to current_team: this
    # clears notifications across every team the user belongs to, so no single team owns it. The
    # honest reading is "the team the user was looking at when they cleared the lot".
    track_feature('notification', 'read_all', count: marked) if marked.positive?

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
