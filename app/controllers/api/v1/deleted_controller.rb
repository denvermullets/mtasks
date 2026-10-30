module Api
  module V1
    # Tombstone feeds: what was deleted since the client's last sync. `index` is the team feed;
    # `user_index` covers the user's own records (saved views, later dashboards).
    class DeletedController < BaseController
      before_action :set_current_team, only: :index
      before_action :set_since

      def index
        render_feed TeamDeletedFeed.new(current_team, since: @since)
      end

      def user_index
        render_feed UserDeletedFeed.new(current_user, team_ids: accessible_teams.select(:id), since: @since)
      end

      private

      def render_feed(feed)
        entries = feed.entries
        @tracked_result_count = entries.size
        render json: entries
      end

      def set_since
        @since = parse_time_param(:since)
      end
    end
  end
end
