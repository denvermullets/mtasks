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
          milestone: serialize_record(@issue.milestone, :name),
          parent_issue: serialize_record(@issue.parent_issue, :identifier),
          blocking_issues: @issue.blocking_issues.map { |i| { id: i.id, identifier: i.identifier, title: i.title } },
          blocked_issues: @issue.blocked_issues.map { |i| { id: i.id, identifier: i.identifier, title: i.title } },
          started_at: @issue.started_at,
          completed_at: @issue.completed_at,
          canceled_at: @issue.canceled_at
        }
      end

      def serialize_record(record, attribute)
        return nil unless record

        { id: record.id, attribute => record.public_send(attribute) }
      end
    end
  end
end
