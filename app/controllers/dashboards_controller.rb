# Dashboards are personal (user-owned, not team-scoped), so every lookup goes through
# current_user.dashboards and another user's id is simply not found.
class DashboardsController < ApplicationController
  include DashboardPage

  before_action :set_dashboard, only: %i[show update destroy]

  def index
    first = sidebar_dashboards.first
    return unless first # renders the empty state

    flash.keep # survives destroy -> index -> show
    redirect_to dashboard_path(first)
  end

  def show
    load_dashboard_page
  end

  def create
    # Not current_user.dashboards.new: that would put the unsaved record in the association
    # target, and the sidebar would render it on a 422.
    @dashboard = Dashboard.new(dashboard_params.merge(user: current_user))
    @dashboard.position = current_user.dashboards.maximum(:position).to_i + 1

    if @dashboard.save
      redirect_to dashboard_path(@dashboard), notice: 'Dashboard created'
    else
      @form_dashboard = @dashboard
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @dashboard.update(dashboard_params)
      redirect_to dashboard_path(@dashboard), notice: 'Dashboard updated'
    else
      @form_dashboard = @dashboard
      @dashboard = current_user.dashboards.find(params[:id]) # pristine copy for the page behind the modal
      load_dashboard_page
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @dashboard.destroy
    redirect_to dashboards_path, notice: 'Dashboard deleted'
  end

  private

  def set_dashboard
    @dashboard = current_user.dashboards.find(params[:id])
  end

  def dashboard_params
    params.require(:dashboard).permit(:name, :description)
  end
end
