class HourglassThreadLinksController < ApplicationController
  include TeamScoped

  before_action :require_team!
  before_action :set_team
  before_action :set_issue
  before_action :set_integration, only: %i[new create]

  def new
    render layout: false
  end

  def create
    return render_create_error(missing_integration_error) unless @integration

    result = HourglassLinks::CreateThreadService.call(
      issue: @issue,
      hourglass_thread_id: params[:hourglass_thread_id],
      integration: @integration,
      current_user: current_user
    )

    if result.error
      render_create_error(result.error)
    else
      @issue_thread_link = result.link
      track_integration('hourglass-integration', 'link', provider: 'hourglass', entity: 'issue')
      respond_to do |format|
        format.turbo_stream { render :create }
        format.html { redirect_to team_issue_path(@team, @issue), notice: 'Thread linked.' }
      end
    end
  end

  def destroy
    link = HourglassLink.for_issue(@issue).first
    track_thread_unlinked(link) if link

    @issue_thread_link = nil
    respond_to do |format|
      format.turbo_stream { render :destroy }
      format.html { redirect_to team_issue_path(@team, @issue), notice: 'Thread unlinked.' }
    end
  end

  private

  def track_thread_unlinked(link)
    result = HourglassLinks::DestroyService.call(link: link)
    return if result.error

    track_integration('hourglass-integration', 'unlink', provider: 'hourglass', entity: 'issue')
  end

  def set_team
    @team = current_team
  end

  def set_issue
    @issue = current_team.issues.find(params[:issue_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to team_issues_path(current_team), alert: 'Issue not found.'
  end

  # A thread lives under the channel its project is linked to, so pull the integration from that
  # project's channel link. When the project isn't linked, the user picks one of the team's
  # subscribed integrations; there is no default.
  def set_integration
    @integrations = current_team.hourglass_integrations.order(:created_at).to_a
    @project_integration = issue_project_integration
    @integration = @project_integration || chosen_integration
  end

  def issue_project_integration
    @issue.project&.hourglass_channel_link&.hourglass_integration
  end

  def chosen_integration
    id = params[:hourglass_integration_id]
    return if id.blank?

    @integrations.find { |integration| integration.id.to_s == id.to_s }
  end

  def missing_integration_error
    return 'This team is not subscribed to a Hourglass server.' if @integrations.empty?

    'Choose which Hourglass server the thread is on.'
  end

  def modal_frame_id
    'hourglass_thread_link_modal'
  end

  def render_create_error(error)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          modal_frame_id,
          partial: 'hourglass_thread_links/error',
          locals: { error: error, issue: @issue }
        )
      end
      format.html { redirect_to team_issue_path(@team, @issue), alert: error }
    end
  end
end
