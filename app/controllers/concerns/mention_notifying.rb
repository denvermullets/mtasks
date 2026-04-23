module MentionNotifying
  extend ActiveSupport::Concern

  private

  def notify_mentions_on(issue, text:, comment: nil, previous_text: nil)
    MentionNotificationService.call(
      issue: issue, actor: Current.user, text: text, comment: comment, previous_text: previous_text
    )
  end
end
