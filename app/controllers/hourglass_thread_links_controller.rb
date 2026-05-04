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
      respond_to do |format|
        format.turbo_stream { render :create }
        format.html { redirect_to team_issue_path(@team, @issue), notice: 'Thread linked.' }
      end
    end
  end

  def destroy
    link = HourglassLink.for_issue(@issue).first
    HourglassLinks::DestroyService.call(link: link) if link

    @issue_thread_link = nil
    respond_to do |format|
      format.turbo_stream { render :destroy }
      format.html { redirect_to team_issue_path(@team, @issue), notice: 'Thread unlinked.' }
    end
  end

  private

  def set_team
    @team = current_team
  end

  def set_issue
    @issue = current_team.issues.find(params[:issue_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to team_issues_path(current_team), alert: 'Issue not found.'
  end

  def set_integration
    @integration = current_team.workspace.hourglass_integrations.active.first
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
