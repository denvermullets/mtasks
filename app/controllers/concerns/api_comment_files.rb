# Shared by the issue and project comment endpoints: `files: [signed_id]` on create, and the
# author-or-admin rule for removing a comment attachment.
module ApiCommentFiles
  extend ActiveSupport::Concern

  private

  # [] when no files were sent; nil when any id doesn't resolve, so a bad batch creates nothing.
  def find_blobs
    ids = Array(params[:files]).compact_blank
    blobs = ids.map { |id| ActiveStorage::Blob.find_signed(id) }
    blobs.all? ? blobs.uniq : nil
  end

  def render_invalid_files
    render json: { error: 'Unprocessable Entity', errors: ['files must be valid signed ids'] },
           status: :unprocessable_entity
  end

  def can_modify?(comment)
    comment.user_id == Current.user.id || current_team.admin?(Current.user)
  end

  def render_forbidden(message)
    render json: { error: 'Forbidden', message: message }, status: :forbidden
  end

  # Mirrors the web: attaching files to a comment is one issue-attachment/create with entity comment.
  def track_comment_files(blobs)
    track_api_feature('issue-attachment', 'create', entity: 'comment', count: blobs.size) if blobs.any?
  end
end
