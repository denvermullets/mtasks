class IssueTurboStreamService
  attr_reader :issue, :current_user, :current_team, :form_collections

  def initialize(issue, current_user, current_team, form_collections = {})
    @issue = issue
    @current_user = current_user
    @current_team = current_team
    @form_collections = form_collections
  end

  def update_streams(view_context)
    issue.reload
    [
      render_card_stream(view_context),
      render_sidebar_stream(view_context)
    ]
  end

  private

  def render_card_stream(view_context)
    view_context.turbo_stream.replace(
      "issue_#{issue.id}",
      partial: 'issues/issue_card',
      locals: { issue: issue, visible_properties: visible_properties }
    )
  end

  def render_sidebar_stream(view_context)
    view_context.turbo_stream.replace(
      'issue_sidebar',
      partial: 'issues/sidebar',
      locals: {
        issue: issue,
        lanes: form_collections[:lanes],
        team_members: form_collections[:team_members],
        projects: form_collections[:projects]
      }
    )
  end

  def visible_properties
    UserPreference.for_user_and_team(current_user, current_team).visible_properties_array
  end
end
