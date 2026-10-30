module Api
  module V1
    # Project change history: paper_trail update versions, oldest first, same entry shape as issue
    # activity. `limit` returns the newest `limit` matches; `before_id` (an entry's `cursor`, or a bare
    # version id) pages to older entries and X-Next-Before-Id carries the next cursor when one exists.
    class ProjectActivityController < BaseController
      DEFAULT_LIMIT = IssueActivityFeed::DEFAULT_LIMIT
      MAX_LIMIT = IssueActivityFeed::MAX_LIMIT

      before_action :set_current_team
      before_action :set_project

      def index
        since = parse_time_param(:since)
        return if performed?

        scope = filtered_versions(since)
        return if performed?

        versions = scope.reorder(id: :desc).limit(limit + 1).to_a # one extra row says an older page exists
        add_next_cursor_header(versions)
        render json: versions.first(limit).reverse.map { |v| ProjectActivityEntrySerializer.new(v).as_json }
      end

      private

      def add_next_cursor_header(versions)
        return unless versions.size > limit

        response.headers['X-Next-Before-Id'] = "version:#{versions[limit - 1].id}"
      end

      def filtered_versions(since)
        scope = @project.versions.where(event: 'update')
        scope = scope.where('versions.created_at > ?', since) if since
        return scope if params[:before_id].blank?

        boundary = scope.find_by(id: params[:before_id].to_s.delete_prefix('version:'))
        return scope.where('versions.id < ?', boundary.id) if boundary

        render json: { error: 'Not Found', message: 'before_id not found' }, status: :not_found
      end

      def set_project
        @project = current_team.projects.find(params[:project_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Project not found' }, status: :not_found
      end

      def limit
        params[:limit].to_i.positive? ? [params[:limit].to_i, MAX_LIMIT].min : DEFAULT_LIMIT
      end
    end
  end
end
