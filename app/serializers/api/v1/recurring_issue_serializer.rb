module Api
  module V1
    class RecurringIssueSerializer
      def initialize(recurring_issue)
        @recurring_issue = recurring_issue
      end

      def as_json
        issue_json.merge(schedule_json).merge(relations_json)
      end

      private

      def issue_json
        r = @recurring_issue
        { id: r.id, title: r.title, description: r.description, priority: r.priority }
      end

      def schedule_json
        r = @recurring_issue
        {
          frequency: r.frequency, interval: r.interval, weekday: r.weekday, day_of_month: r.day_of_month,
          time_zone: r.time_zone, active: r.active, next_run_on: r.next_run_on, last_run_at: r.last_run_at,
          schedule_summary: r.schedule_summary
        }
      end

      def relations_json
        r = @recurring_issue
        {
          assignee: user_json(r.assignee),
          project: r.project && { id: r.project.id, name: r.project.name },
          lane: r.lane && { id: r.lane.id, name: r.lane.name },
          label_ids: r.label_ids,
          creator: user_json(r.creator),
          created_at: r.created_at,
          updated_at: r.updated_at
        }
      end

      def user_json(user)
        user && { id: user.id, name: user.name }
      end
    end
  end
end
