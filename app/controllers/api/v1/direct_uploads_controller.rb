module Api
  module V1
    # Token-authenticated twin of ActiveStorage::DirectUploadsController. The stock class inherits
    # ActiveStorage::BaseController (ActionController::Base, unauthenticated), so this builds the
    # same blob + signed upload target on top of the API base controller instead. The client PUTs
    # the bytes to the returned URL, then attaches the signed_id in a later request.
    class DirectUploadsController < BaseController
      MAX_BYTES = 25.megabytes

      # SVG and HTML are deliberately absent: both can carry script and would be served from our
      # storage origin.
      ALLOWED_CONTENT_TYPES = %w[
        image/png image/jpeg image/gif image/webp image/heic image/avif
        application/pdf
        text/plain text/markdown text/csv application/json
        application/zip
        application/msword
        application/vnd.openxmlformats-officedocument.wordprocessingml.document
        application/vnd.ms-excel
        application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
        application/vnd.ms-powerpoint
        application/vnd.openxmlformats-officedocument.presentationml.presentation
        video/mp4 video/quicktime video/webm
      ].freeze

      before_action :validate_blob_params

      def create
        ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host, port: request.port }
        blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_args)

        render json: direct_upload_json(blob)
      end

      private

      def blob_params
        params.fetch(:blob, {}).permit(:filename, :byte_size, :checksum, :content_type, metadata: {})
      end

      def blob_args
        blob_params.to_h.symbolize_keys
      end

      def validate_blob_params
        args = blob_params
        errors = []
        errors << 'filename, checksum and content_type are required' if required_blank?(args)
        errors << "content_type #{args[:content_type]} is not allowed" if disallowed_type?(args[:content_type])
        unless args[:byte_size].to_i.between?(1, MAX_BYTES)
          errors << "byte_size must be between 1 and #{MAX_BYTES / 1.megabyte} MB"
        end
        return if errors.empty?

        render json: { error: 'Unprocessable Entity', errors: errors }, status: :unprocessable_entity
      end

      def required_blank?(args)
        args.values_at(:filename, :checksum, :content_type).any?(&:blank?)
      end

      def disallowed_type?(content_type)
        content_type.present? && ALLOWED_CONTENT_TYPES.exclude?(content_type.to_s.downcase)
      end

      def direct_upload_json(blob)
        blob.as_json(root: false, methods: :signed_id).merge(
          direct_upload: { url: blob.service_url_for_direct_upload, headers: blob.service_headers_for_direct_upload }
        )
      end
    end
  end
end
