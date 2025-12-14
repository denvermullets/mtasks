class ImportsController < ApplicationController
  before_action :require_team!

  def new; end

  def create
    unless params[:csv_file].present?
      redirect_to new_import_path, alert: 'Please select a CSV file'
      return
    end

    csv_file = params[:csv_file]
    importer = IssueImporter.new(current_team)
    result = importer.import(csv_file.read)

    if result[:success]
      redirect_to root_path, notice: "Successfully imported #{result[:imported]} issues"
    else
      flash.now[:alert] =
        "Import completed with errors. Imported: #{result[:imported]}, Errors: #{result[:errors].count}"
      @errors = result[:errors]
      render :new, status: :unprocessable_entity
    end
  end
end
