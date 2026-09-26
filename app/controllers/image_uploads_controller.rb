# Direct-upload endpoint for images pasted into markdown descriptions. Rails' stock endpoint is
# unauthenticated and accepts any file, so this one requires a session and only takes images.
class ImageUploadsController < ActiveStorage::DirectUploadsController
  include Authentication

  MAX_BYTES = 10.megabytes

  before_action :require_image

  private

  def require_image
    blob = params.fetch(:blob, {})
    return if blob[:content_type].to_s.start_with?('image/') && blob[:byte_size].to_i.between?(1, MAX_BYTES)

    render json: { error: 'Only images up to 10 MB can be pasted' }, status: :unprocessable_content
  end
end
