module Api
  module V1
    class IssueSerializer
      def initialize(issue, detailed: false)
        @issue = issue
        @detailed = detailed
      end

      def as_json
        base_json.merge(@detailed ? detail_json : {})
      end

      private

      def base_json
        {
          id: @issue.id,
          identifier: @issue.identifier,
          title: @issue.title,
          priority: @issue.priority,
          estimate: @issue.estimate,
          due_date: @issue.due_date,
          lane: serialize_record(@issue.lane, :name),
          assignee: serialize_record(@issue.assignee, :name),
          creator: serialize_record(@issue.creator, :name),
          project: serialize_record(@issue.project, :name),
          labels: @issue.labels.map { |l| { id: l.id, name: l.name } },
          created_at: @issue.created_at,
          updated_at: @issue.updated_at
        }
      end

      def detail_json
        {
          description: @issue.description,
          parent_issue: serialize_record(@issue.parent_issue, :identifier),
          # Each entry carries the IssueDependency record id (dependency_id) so it can be removed.
          # blocking_issues = issues that block this one (via blocked_dependencies -> blocking_issue)
          # blocked_issues  = issues this one blocks (via blocking_dependencies -> blocked_issue)
          blocking_issues: @issue.blocked_dependencies.map { |d| serialize_dependency_issue(d, d.blocking_issue) },
          blocked_issues: @issue.blocking_dependencies.map { |d| serialize_dependency_issue(d, d.blocked_issue) },
          # related_issues / duplicates carry `direction` relative to this issue
          # (relates, or duplicates / duplicated_by).
          related_issues: serialize_links(:relates),
          duplicates: serialize_links(:duplicates),
          started_at: @issue.started_at,
          completed_at: @issue.completed_at,
          canceled_at: @issue.canceled_at
        }
      end

      def serialize_record(record, attribute)
        return nil unless record

        { id: record.id, attribute => record.public_send(attribute) }
      end

      def serialize_dependency_issue(dependency, issue)
        { id: issue.id, identifier: issue.identifier, title: issue.title, dependency_id: dependency.id }
      end

      def serialize_links(kind)
        outgoing = @issue.outgoing_links.public_send(kind).includes(:blocked_issue).map { |d| [d, d.blocked_issue] }
        incoming = @issue.incoming_links.public_send(kind).includes(:blocking_issue).map { |d| [d, d.blocking_issue] }

        (outgoing + incoming).sort_by { |d, _| d.id }.map do |dependency, other|
          serialize_dependency_issue(dependency, other)
            .merge(direction: IssueDependencies::Link.direction_for(dependency, @issue))
        end
      end
    end
  end
end
