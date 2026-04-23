class MentionNotificationService < Service
  def initialize(issue:, actor:, text:, comment: nil, previous_text: nil)
    @issue = issue
    @actor = actor
    @text = text
    @comment = comment
    @previous_text = previous_text
  end

  def call
    return if @previous_text == @text

    mentioned_users.each do |user|
      Notification.create!(
        user: user,
        actor: @actor,
        issue: @issue,
        comment: @comment,
        action: 'mentioned',
        message: build_message
      )
    end
  end

  private

  def mentioned_users
    current = UserMentionParser.find_users(@text, @issue.team)
    new_mentions = if @previous_text
                     previous = UserMentionParser.find_users(@previous_text, @issue.team)
                     current - previous
                   else
                     current
                   end
    new_mentions.reject { |u| u == @actor }
  end

  def build_message
    source = @comment ? 'a comment on' : 'the description of'
    "#{@actor.name} mentioned you in #{source} #{@issue.identifier}"
  end
end
