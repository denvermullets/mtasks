module Discussion
  class CommentPayloadBuilder < Service
    def initialize(comment:)
      @comment = comment
    end

    def call
      { body: fallback_body, data: data }
    end

    private

    def data
      payload = {
        source: 'mtasks',
        event_type: event_type,
        actor_email: @comment.user&.email,
        actor_name: @comment.user&.name,
        actor_username: username_for(@comment.user),
        comment_id: @comment.id,
        comment_body: rewrite_mentions(@comment.body.to_s)
      }
      payload.merge!(issue_fields).merge!(project_fields)
      payload.compact
    end

    def event_type
      @comment.issue ? 'issue.commented' : 'project.commented'
    end

    def issue_fields
      issue = @comment.issue
      return {} unless issue

      {
        issue_id: issue.id,
        identifier: issue.identifier,
        title: issue.title,
        team_slug: issue.team&.identifier
      }
    end

    def project_fields
      project = @comment.project || @comment.issue&.project
      return {} unless project

      { project_name: project.name }
    end

    def fallback_body
      "#{@comment.user&.name.presence || 'Someone'} commented in JAIT"
    end

    def username_for(user)
      return nil unless user&.email

      user.email.split('@').first
    end

    def rewrite_mentions(text)
      team = team_for_comment
      return text if team.nil?

      mentioned = UserMentionParser.find_users(text, team)
      return text if mentioned.empty?

      maps = mention_map_for(mentioned)
      mentioned.reduce(text) { |acc, user| replace_mention(acc, user, maps[user.id]) }
    end

    def team_for_comment
      @comment.issue&.team || @comment.project&.team
    end

    def mention_map_for(users)
      HourglassUserMap.where(mtasks_user_id: users.map(&:id)).index_by(&:mtasks_user_id)
    end

    def replace_mention(text, user, map)
      return text if map.nil? || map.email.blank?

      pattern = /(?<!\w)@#{Regexp.escape(user.name)}(?!\w)/i
      text.gsub(pattern, "@#{map.email}")
    end
  end
end
