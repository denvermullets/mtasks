module Api
  module V1
    class ProjectSerializer
      def initialize(project, detailed: false)
        @project = project
        @detailed = detailed
      end

      def as_json
        base_json.merge(@detailed ? detail_json : {})
      end

      private

      def base_json
        {
          id: @project.id,
          name: @project.name,
          description: @project.description,
          status: @project.status,
          priority: @project.priority,
          lead: serialize_record(@project.lead, :name),
          start_date: @project.start_date,
          due_date: @project.due_date,
          velocity_score: @project.velocity_score,
          completed_issues_count: @project.completed_issues_count,
          total_issues_count: @project.total_issues_count,
          progress_percentage: @project.progress_percentage,
          behind_schedule: @project.behind_schedule?,
          roadmap_commitment: @project.roadmap_commitment,
          created_at: @project.created_at,
          updated_at: @project.updated_at
        }
      end

      def detail_json
        {
          milestone: serialize_record(@project.milestone, :name),
          labels: @project.labels.map { |l| { id: l.id, name: l.name } },
          issues_count: @project.issues.not_archived.count
        }
      end

      def serialize_record(record, attribute)
        return nil unless record

        { id: record.id, attribute => record.public_send(attribute) }
      end
    end
  end
end
