module Api
  module V1
    class SavedViewSerializer
      def initialize(saved_view)
        @saved_view = saved_view
      end

      def as_json(*)
        {
          id: @saved_view.id, team_id: @saved_view.team_id, name: @saved_view.name,
          query: @saved_view.query, position: @saved_view.position,
          created_at: @saved_view.created_at.iso8601, updated_at: @saved_view.updated_at.iso8601
        }
      end
    end
  end
end
