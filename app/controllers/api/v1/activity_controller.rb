module Api
  module V1
    class ActivityController < BaseController
      before_action :set_current_team
      before_action :set_issue

      # Entries are oldest first. `limit` returns the newest `limit` matches; `before_id` (an entry's
      # `cursor`, or a bare version id) pages to the entries before it, and X-Next-Before-Id carries
      # the cursor for the next older page when one exists.
      def index
        page = IssueActivityFeed.call(issue: @issue, types: IssueActivityFeed.parse_types(params[:types]),
                                      since: parse_time(params[:since]), limit: params[:limit],
                                      before: params[:before_id])
        return render json: { error: 'Not Found', message: 'before_id not found' }, status: :not_found unless page

        response.headers['X-Next-Before-Id'] = page.next_before if page.next_before
        render json: page.items.map { |e| ActivityEntrySerializer.for(e, issue: @issue) }
      end

      private

      def set_issue
        @issue = current_team.issues.find(params[:issue_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found
      end

      def parse_time(value)
        Time.iso8601(value) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
