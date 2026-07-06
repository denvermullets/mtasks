module Api
  module V1
    class IssueDependenciesController < BaseController
      before_action :set_current_team
      before_action :set_issue

      def index
        dependencies = (@issue.blocking_dependencies + @issue.blocked_dependencies)
                       .sort_by(&:id)
                       .map { |dep| serialize_dependency(dep) }

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
          dependency.destroy
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
