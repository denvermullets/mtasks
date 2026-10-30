module Api
  module V1
    class NotificationsController < BaseController
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 200

      def index
        scope = inbox
        unread_count = scope.unread.count
        server_time = Time.current

        # Reading a notification moves unread_count, and mark-all-read bumps updated_at, so this
        # tuple changes whenever the inbox does. The row count covers hard deletes.
        return unless stale?(etag: [unread_count, scope.count, scope.maximum(:updated_at)&.iso8601(6)])

        notifications = filtered(scope).includes(:actor, :issue).to_a
        @tracked_result_count = notifications.size
        render json: {
          notifications: notifications.map { |n| serialize(n) },
          meta: { unread_count: unread_count, server_time: server_time.iso8601(3) }
        }
      end

      private

      # Notifications belong to a user, but the scoping unit is the issue's team, so a team-scoped
      # token only ever sees (and counts) the teams it was issued for.
      def inbox
        current_user.notifications.joins(:issue).where(issues: { team_id: accessible_teams.select(:id) })
      end

      def filtered(scope)
        scope = scope.unread if params[:unread].to_s == '1'
        scope = scope.where(notifications: { updated_at: updated_since.. }) if updated_since
        scope = scope.where(notifications: { id: ...params[:before_id].to_i }) if params[:before_id].present?
        scope.reorder(created_at: :desc, id: :desc).limit(limit)
      end

      def updated_since
        return @updated_since if defined?(@updated_since)

        @updated_since = params[:updated_since].present? ? Time.zone.parse(params[:updated_since].to_s) : nil
      rescue ArgumentError
        @updated_since = nil
      end

      def limit
        requested = params[:limit].to_i
        requested.positive? ? [requested, MAX_LIMIT].min : DEFAULT_LIMIT
      end

      def serialize(notification)
        issue = notification.issue
        {
          id: notification.id, action: notification.action, message: notification.message,
          read_at: notification.read_at&.iso8601, created_at: notification.created_at.iso8601,
          updated_at: notification.updated_at.iso8601,
          actor: { id: notification.actor_id, name: notification.actor.name },
          issue: { id: issue.id, identifier: issue.identifier, title: issue.title, team_id: issue.team_id },
          comment_id: notification.comment_id, version_id: notification.version_id
        }
      end
    end
  end
end
