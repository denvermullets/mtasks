module Api
  module V1
    class CommentSerializer
      def initialize(comment, include_replies: true)
        @comment = comment
        @include_replies = include_replies
      end

      def as_json
        json = {
          id: @comment.id,
          body: @comment.body,
          parent_id: @comment.parent_id,
          user: serialize_user(@comment.user),
          created_at: @comment.created_at,
          updated_at: @comment.updated_at
        }

        if @include_replies
          json[:replies] = @comment.replies
                                   .order(:created_at)
                                   .map { |reply| self.class.new(reply, include_replies: false).as_json }
        end

        json
      end

      private

      def serialize_user(user)
        return nil unless user

        { id: user.id, name: user.name, email: user.email }
      end
    end
  end
end
