module Api
  module V1
    # Attach already-uploaded blobs (see DirectUploadsController) to a project, or remove one. Both
    # touch the project explicitly so an updated_since pull sees the change.
    class ProjectAttachmentsController < BaseController
      before_action :set_current_team
      before_action :set_project

      def create
        blobs = find_blobs
        return render_invalid_signed_ids if blobs.nil?

        @project.files.attach(blobs)
        @project.touch
        track_api_feature('project-management', 'update', entity: 'project', count: blobs.size)
        render json: attached_since(blobs).map { |a| AttachmentSerializer.new(a).as_json }, status: :created
      end

      def destroy
        attachment = @project.files_attachments.find(params[:id])
        attachment.purge
        @project.touch
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Attachment not found' }, status: :not_found
      end

      private

      def set_project
        @project = current_team.projects.find_by(id: params[:project_id])
        render json: { error: 'Not Found', message: 'Project not found' }, status: :not_found unless @project
      end

      # nil when the list is empty or any id doesn't resolve, so a bad batch attaches nothing.
      def find_blobs
        ids = Array(params[:signed_ids]).compact_blank
        return nil if ids.empty?

        blobs = ids.map { |id| ActiveStorage::Blob.find_signed(id) }
        blobs.all? ? blobs.uniq : nil
      end

      def attached_since(blobs)
        @project.files_attachments.includes(:blob).where(blob_id: blobs.map(&:id)).order(:id)
      end

      def render_invalid_signed_ids
        render json: { error: 'Unprocessable Entity', errors: ['signed_ids must be a non-empty list of valid ids'] },
               status: :unprocessable_entity
      end
    end
  end
end
