module Api
  module V1
    # One ActiveStorage::Attachment (the join row, whose id is what DELETE takes), not the blob.
    class AttachmentSerializer
      def initialize(attachment)
        @attachment = attachment
      end

      def as_json
        blob = @attachment.blob
        {
          id: @attachment.id, blob_id: blob.id, filename: blob.filename.to_s, content_type: blob.content_type,
          byte_size: blob.byte_size, checksum: blob.checksum, created_at: @attachment.created_at,
          download_url: "/api/v1/attachments/#{@attachment.id}/download"
        }
      end
    end
  end
end
