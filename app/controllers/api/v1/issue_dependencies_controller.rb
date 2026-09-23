module Api
  module V1
    class IssueDependenciesController < BaseController
      before_action :set_current_team
      before_action :set_issue

      def index
        dependencies = (@issue.blocking_dependencies + @issue.blocked_dependencies)
                       .sort_by(&:id)
                       .map { |dep| serialize_dependency(dep) }

        @tracked_result_count = dependencies.size
        render json: dependencies
      end

      def create
        target_issue = current_team.issues.find(params[:target_issue_id])
        direction = params[:direction]

        dependency = if direction == 'blocked_by'
                       IssueDependency.new(blocking_issue: target_issue, blocked_issue: @issue)
                     else
                       IssueDependency.new(blocking_issue: @issue, blocked_issue: target_issue)
                     end

        if dependency.save
          # Same property shape as the web call site: `direction` plus a `count` that separates a
          # bulk form save from a single gesture. The API links one at a time, so it is always 1.
          tracked_direction = direction == 'blocked_by' ? 'blocked_by' : 'blocking'
          track_api_feature('issue-dependency', 'link', count: 1, direction: tracked_direction)
          render json: serialize_dependency(dependency), status: :created
        else
          render_validation_errors(dependency)
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Target issue not found' }, status: :not_found
      end

      def destroy
        dependency = IssueDependency.find_by(id: params[:id])

        if dependency && (dependency.blocking_issue_id == @issue.id || dependency.blocked_issue_id == @issue.id)
          direction = dependency.blocking_issue_id == @issue.id ? 'blocking' : 'blocked_by'
          dependency.destroy
          track_api_feature('issue-dependency', 'unlink', direction: direction)
          render json: { ok: true, id: dependency.id }
        else
          render json: { error: 'Not Found', message: 'Dependency not found' }, status: :not_found
        end
      end

      private

      def set_issue
        @issue = current_team.issues.find(params[:issue_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found
      end

      def serialize_dependency(dep)
        {
          id: dep.id,
          # Direction relative to the current issue: 'blocking' when this issue blocks the other,
          # 'blocked_by' when this issue is blocked by the other.
          direction: dep.blocking_issue_id == @issue.id ? 'blocking' : 'blocked_by',
          blocking_issue: { id: dep.blocking_issue.id, identifier: dep.blocking_issue.identifier,
                            title: dep.blocking_issue.title },
          blocked_issue: { id: dep.blocked_issue.id, identifier: dep.blocked_issue.identifier,
                           title: dep.blocked_issue.title },
          created_at: dep.created_at
        }
      end
    end
  end
end
