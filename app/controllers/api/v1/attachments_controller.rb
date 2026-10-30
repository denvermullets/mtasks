module Api
  module V1
    # Attach already-uploaded blobs (see DirectUploadsController) to an issue, or remove one. Both
    # touch the issue explicitly so an updated_since pull sees the change.
    class AttachmentsController < BaseController
      before_action :set_current_team
      before_action :set_issue

      def create
        blobs = find_blobs
        return render_invalid_signed_ids if blobs.nil?

        @issue.files.attach(blobs)
        @issue.touch
        track_api_feature('issue-attachment', 'create', entity: 'issue', count: blobs.size)
        render json: attached_since(blobs).map { |a| AttachmentSerializer.new(a).as_json }, status: :created
      end

      def destroy
        attachment = @issue.files_attachments.find(params[:id])
        attachment.purge
        @issue.touch
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found', message: 'Attachment not found' }, status: :not_found
      end

      private

      def set_issue
        @issue = current_team.issues.find_by(id: params[:issue_id])
        render json: { error: 'Not Found', message: 'Issue not found' }, status: :not_found unless @issue
      end

      # nil when the list is empty or any id doesn't resolve, so a bad batch attaches nothing.
      def find_blobs
        ids = Array(params[:signed_ids]).compact_blank
        return nil if ids.empty?

        blobs = ids.map { |id| ActiveStorage::Blob.find_signed(id) }
        blobs.all? ? blobs.uniq : nil
      end

      def attached_since(blobs)
        @issue.files_attachments.includes(:blob).where(blob_id: blobs.map(&:id)).order(:id)
      end

      def render_invalid_signed_ids
        render json: { error: 'Unprocessable Entity', errors: ['signed_ids must be a non-empty list of valid ids'] },
               status: :unprocessable_entity
      end
    end
  end
end
