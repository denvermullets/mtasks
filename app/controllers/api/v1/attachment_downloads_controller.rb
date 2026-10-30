module Api
  module V1
    # Authenticated download for any file attached to an issue, project or comment. Going through
    # the API (rather than a signed blob URL) is what lets a revoked or team-scoped token lose
    # access; the redirect target itself only lives for five minutes.
    class AttachmentDownloadsController < BaseController
      URL_TTL = 5.minutes

      def show
        attachment = ActiveStorage::Attachment.includes(:blob).find_by(id: params[:id], name: 'files')
        return render_not_found unless attachment && accessible?(attachment)

        # Disk-backed services build URLs from this; ActionController::API never sets it.
        ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host, port: request.port }
        redirect_to attachment.blob.url(expires_in: URL_TTL), allow_other_host: true
      end

      private

      def accessible?(attachment)
        team_id = owning_team_id(attachment)
        team_id.present? && accessible_teams.exists?(id: team_id)
      end

      # Issues, projects and comments are the only attachable records; anything else resolves to
      # nil and so to 404. A comment belongs to exactly one of an issue or a project.
      def owning_team_id(attachment)
        case attachment.record_type
        when 'Issue' then Issue.where(id: attachment.record_id).pick(:team_id)
        when 'Project' then Project.where(id: attachment.record_id).pick(:team_id)
        when 'Comment' then comment_team_id(attachment.record_id)
        end
      end

      def comment_team_id(comment_id)
        issue_id, project_id = Comment.where(id: comment_id).pick(:issue_id, :project_id)
        return Issue.where(id: issue_id).pick(:team_id) if issue_id

        Project.where(id: project_id).pick(:team_id) if project_id
      end

      def render_not_found
        render json: { error: 'Not Found', message: 'Attachment not found' }, status: :not_found
      end
    end
  end
end
