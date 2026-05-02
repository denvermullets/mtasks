module Api
  module V1
    class DecisionSerializer
      def initialize(decision)
        @decision = decision
      end

      def as_json
        {
          id: @decision.id,
          hourglass_message_id: @decision.hourglass_message_id,
          body_snapshot: @decision.body_snapshot,
          pinned_at: @decision.pinned_at,
          pinned_by_user: pinned_by_user_json,
          unpinned_at: @decision.unpinned_at,
          team_id: @decision.team_id,
          issue_id: @decision.issue_id,
          project_id: @decision.project_id,
          idempotency_key: @decision.idempotency_key,
          created_at: @decision.created_at,
          updated_at: @decision.updated_at
        }
      end

      private

      def pinned_by_user_json
        return nil unless @decision.pinned_by_user

        { id: @decision.pinned_by_user.id, name: @decision.pinned_by_user.name }
      end
    end
  end
end
