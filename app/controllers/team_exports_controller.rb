class TeamExportsController < ApplicationController
  before_action :set_team

  def show
    @issue_count = @team.issues.count
  end

  def create
    exporter = IssueExporter.new(@team)
    filename = "#{@team.identifier.downcase}-issues-#{Date.current.iso8601}.csv"
    send_data exporter.to_csv, filename: filename, type: 'text/csv', disposition: 'attachment'
  end

  private

  def set_team
    @team = user_teams.find(params[:team_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "You don't have access to that team"
  end
end
