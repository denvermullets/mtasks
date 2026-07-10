class HourglassChannelLinksController < ApplicationController
  include TeamScoped

  before_action :require_team!
  before_action :set_team
  before_action :set_project
  before_action :set_integrations, only: %i[new create channels]

  def new
    @channels = fetch_channels(query: params[:q])
    render layout: false
  end

  def channels
    render json: fetch_channels(query: params[:q])
  end

  def create
    integration = link_integration
    return render_create_error('Select a channel from a connected Hourglass server.') unless integration

    result = HourglassLinks::CreateService.call(
      project: @project,
      channel_id: params.require(:hourglass_channel_id),
      channel_name: params[:hourglass_channel_name].to_s,
      integration: integration,
      current_user: current_user
    )

    if result.error
      render_create_error(result.error)
    else
      @channel_link = result.link
      respond_to do |format|
        format.turbo_stream { render :create }
        format.html { redirect_to discussion_team_project_path(@team, @project), notice: 'Channel linked.' }
      end
    end
  end

  def destroy
    link = @project.hourglass_channel_link
    HourglassLinks::DestroyService.call(link: link) if link

    @channel_link = nil
    respond_to do |format|
      format.turbo_stream { render :destroy }
      format.html { redirect_to discussion_team_project_path(@team, @project), notice: 'Channel unlinked.' }
    end
  end

  private

  def set_team
    @team = current_team
  end

  def set_project
    @project = current_team.projects.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to team_projects_path(current_team), alert: 'Project not found.'
  end

  def set_integrations
    @integrations = current_team.workspace.hourglass_integrations.active.order(:created_at)
  end

  # The channel picker submits the integration that owns the chosen channel.
  # Fall back to the sole integration when only one is connected.
  def link_integration
    id = params[:hourglass_integration_id]
    return @integrations.first if id.blank?

    @integrations.find { |integration| integration.id.to_s == id.to_s }
  end

  def modal_frame_id
    'hourglass_channel_link_modal'
  end

  def render_create_error(error)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          modal_frame_id,
          partial: 'hourglass_channel_links/error',
          locals: { error: error, project: @project }
        )
      end
      format.html { redirect_to discussion_team_project_path(@team, @project), alert: error }
    end
  end

  def fetch_channels(query: nil)
    channels = Array(@integrations).flat_map { |integration| channels_for(integration) }
    return channels if query.blank?

    q = query.to_s.downcase
    channels.select { |c| c[:name].to_s.downcase.include?(q) || c[:server_name].to_s.downcase.include?(q) }
  end

  def channels_for(integration)
    client = Hourglass::ApiClient.for_integration(integration)
    raw = begin
      client.discover_channels!
    rescue Hourglass::ApiClient::Error => e
      Rails.logger.warn("Hourglass channel fetch failed (integration #{integration.id}): #{e.message}")
      []
    end

    raw.map { |c| normalize_channel(c, integration) }
  end

  def normalize_channel(raw, integration)
    {
      id: raw['id'] || raw[:id],
      name: raw['name'] || raw[:name],
      topic: raw['topic'] || raw[:topic],
      integration_id: integration.id,
      server_name: integration.hourglass_server_name.presence || integration.hourglass_server_id
    }
  end
end
