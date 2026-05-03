module Discussion
  class ChatMessageFormatter < Service
    def initialize(comment:)
      @comment = comment
    end

    def call
      "#{author_name} said in JAIT: #{rewrite_mentions(@comment.body.to_s)}"
    end

    private

    def author_name
      @comment.user&.name.presence || 'Someone'
    end

    def rewrite_mentions(text)
      team = @comment.project&.team
      return text if team.nil?

      mentioned = UserMentionParser.find_users(text, team)
      return text if mentioned.empty?

      maps_by_user_id = HourglassUserMap.where(mtasks_user_id: mentioned.map(&:id)).index_by(&:mtasks_user_id)
      mentioned.reduce(text) { |acc, user| replace_mention(acc, user, maps_by_user_id[user.id]) }
    end

    def replace_mention(text, user, map)
      return text if map.nil? || map.email.blank?

      pattern = /(?<!\w)@#{Regexp.escape(user.name)}(?!\w)/i
      text.gsub(pattern, "@#{map.email}")
    end
  end
end
