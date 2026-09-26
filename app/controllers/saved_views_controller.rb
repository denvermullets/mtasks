# Personal saved views of a team's issues board. Views belong to the user, so every lookup goes
# through current_user.saved_views; the team comes from the URL (set_current_team checks membership).
# The form posts the board's current query string, captured client-side since filter changes only
# pushState the URL and never re-render the top bar.
class SavedViewsController < ApplicationController
  before_action :require_team!
  before_action :set_saved_view, only: %i[update destroy]

  def create
    view = SavedView.new(
      user: current_user, team: current_team, name: saved_view_params[:name],
      query: SavedView.query_from(saved_view_params[:query]),
      position: current_user.saved_views.maximum(:position).to_i + 1
    )

    if view.save
      redirect_to view.path, notice: 'View saved', status: :see_other
    else
      redirect_back_to_board alert: "Couldn't save view: #{view.errors.full_messages.to_sentence}"
    end
  end

  # Re-captures the board's current filters into the view (and renames it when a name is sent).
  def update
    attrs = {}
    attrs[:name] = saved_view_params[:name] if saved_view_params.key?(:name)
    attrs[:query] = SavedView.query_from(saved_view_params[:query]) if saved_view_params.key?(:query)

    if @saved_view.update(attrs)
      redirect_to @saved_view.path, notice: 'View updated', status: :see_other
    else
      redirect_back_to_board alert: "Couldn't update view: #{@saved_view.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    @saved_view.destroy
    redirect_back_to_board notice: 'View deleted'
  end

  private

  def set_saved_view
    @saved_view = current_user.saved_views.where(team: current_team).find(params[:id])
  end

  def saved_view_params
    params.require(:saved_view).permit(:name, :query)
  end

  def redirect_back_to_board(**flash)
    query = SavedView.query_from(params.dig(:saved_view, :query))
    redirect_to team_issues_path(current_team, query), status: :see_other, **flash
  end
end
