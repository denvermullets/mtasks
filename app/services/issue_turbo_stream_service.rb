class IssueTurboStreamService
  include ActionView::RecordIdentifier

  attr_reader :issue, :current_user, :current_team, :form_collections, :view_context

  def initialize(issue, current_user, current_team, view_context, form_collections = {})
    @issue = issue
    @current_user = current_user
    @current_team = current_team
    @view_context = view_context
    @form_collections = form_collections
  end

  def update_streams
    issue.reload
    [card_stream, list_row_stream, sidebar_stream]
  end

  private

  def card_stream
    view_context.turbo_stream.replace(
      "issue_#{issue.id}",
      partial: 'issues/issue_card',
      locals: { issue: issue, visible_properties: visible_properties, labels: form_collections[:labels] }
    )
  end

  def list_row_stream
    view_context.turbo_stream.replace(
      "issue_row_#{issue.id}",
      partial: 'issues/list_row',
      locals: { issue: issue, display_options: { visible_properties: visible_properties },
                labels: form_collections[:labels] }
    )
  end

  def sidebar_stream
    view_context.turbo_stream.replace(
      'issue_sidebar',
      partial: 'issues/sidebar',
      locals: {
        issue: issue,
        lanes: form_collections[:lanes],
        team_members: form_collections[:team_members],
        projects: form_collections[:projects],
        labels: form_collections[:labels]
      }
    )
  end

  def visible_properties
    UserPreference.for_user_and_team(current_user, current_team).visible_properties_array
  end
end
