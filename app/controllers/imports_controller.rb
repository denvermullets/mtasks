class ImportsController < ApplicationController
  before_action :require_team!

  def new; end

  def create
    return redirect_to_file_required unless csv_file_present?

    result = perform_import
    handle_import_result(result)
  end

  private

  def csv_file_present?
    params[:csv_file].present?
  end

  def redirect_to_file_required
    redirect_to new_import_path, alert: 'Please select a CSV file'
  end

  def perform_import
    importer = IssueImporter.new(current_team)
    importer.import(params[:csv_file].read)
  end

  def handle_import_result(result)
    if result[:success]
      redirect_to root_path, notice: "Successfully imported #{result[:imported]} issues"
    else
      show_import_errors(result)
    end
  end

  def show_import_errors(result)
    flash.now[:alert] = "Import completed with errors. Imported: #{result[:imported]}, Errors: #{result[:errors].count}"
    @errors = result[:errors]
    render :new, status: :unprocessable_entity
  end
end
