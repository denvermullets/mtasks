module Api
  module V1
    # Tombstone feed: what was deleted from a team since the client's last sync.
    class DeletedController < BaseController
      before_action :set_current_team

      def index
        response.set_header('X-Server-Time', Time.current.utc.iso8601(6))

        since = nil
        if params.key?(:since)
          since = parse_since
          return render_invalid_since unless since
        end

        entries = TeamDeletedFeed.new(current_team, since: since).entries
        @tracked_result_count = entries.size
        render json: entries
      end

      private

      def parse_since
        Time.iso8601(params[:since].to_s)
      rescue ArgumentError
        nil
      end

      def render_invalid_since
        render json: { error: 'Unprocessable Entity', errors: ['since must be an ISO8601 timestamp'] },
               status: :unprocessable_entity
      end
    end
  end
end
