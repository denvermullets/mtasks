module Api
  module V1
    class IssueDependenciesController < BaseController
      before_action :set_current_team
      before_action :set_issue

      def index
        dependencies = (@issue.outgoing_links.includes(:blocking_issue, :blocked_issue) +
                        @issue.incoming_links.includes(:blocking_issue, :blocked_issue))
                       .sort_by(&:id)
                       .map { |dep| serialize_dependency(dep) }

        @tracked_result_count = dependencies.size
        render json: dependencies
      end

      def create
        target_issue = current_team.issues.find(params[:target_issue_id])
        # Unknown or missing direction means 'blocking', for backward compatibility.
        direction = IssueDependencies::Link.normalize_direction(params[:direction])

        dependency = IssueDependencies::Link.call(issue: @issue, target: target_issue, direction: direction)

        if dependency.persisted?
          # Same property shape as the web call site: `direction` plus a `count` that separates a
          # bulk form save from a single gesture. The API links one at a time, so it is always 1.
          track_api_feature('issue-dependency', 'link', count: 1, direction: direction)
          render json: serialize_dependency(dependency), status: :created
        else
          render_validation_errors(dependency)
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Target issue not found' }, status: :not_found
      end

      def destroy
        dependency = @issue.outgoing_links.find_by(id: params[:id]) || @issue.incoming_links.find_by(id: params[:id])

        if dependency
          direction = IssueDependencies::Link.direction_for(dependency, @issue)
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
          kind: dep.kind,
          # Direction relative to the current issue: blocking/blocked_by for blocks links,
          # relates, or duplicates/duplicated_by.
          direction: IssueDependencies::Link.direction_for(dep, @issue),
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
