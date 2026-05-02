module Api
  module V1
    class DecisionsController < BaseController
      before_action :set_current_team
      before_action :set_parent

      def create
        if (existing = find_by_idempotency_key || find_by_hourglass_message_id)
          return render json: DecisionSerializer.new(existing).as_json, status: :ok
        end

        decision = build_decision
        if decision.save
          broadcast(:append, decision)
          render json: DecisionSerializer.new(decision).as_json, status: :created
        else
          render_validation_errors(decision)
        end
      rescue ActiveRecord::RecordNotUnique
        existing = find_by_idempotency_key || find_by_hourglass_message_id
        render json: DecisionSerializer.new(existing).as_json, status: :ok
      end

      def destroy
        decision = decisions_scope.find(params[:id])
        decision.update!(unpinned_at: Time.current) unless decision.unpinned_at
        broadcast(:remove, decision)
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Not Found' }, status: :not_found
      end

      private

      def set_parent
        @issue = current_team.issues.find_by(id: params[:issue_id]) if params[:issue_id]
        @project = current_team.projects.find_by(id: params[:project_id]) if params[:project_id]
        return if @issue || @project

        render json: { error: 'Not Found' }, status: :not_found
      end

      def decisions_scope
        @issue ? @issue.decisions : @project.decisions
      end

      def find_by_idempotency_key
        key = idempotency_key
        return nil unless key

        decisions_scope.find_by(idempotency_key: key)
      end

      def find_by_hourglass_message_id
        msg_id = params[:hourglass_message_id]
        return nil if msg_id.blank?

        decisions_scope.find_by(hourglass_message_id: msg_id)
      end

      def idempotency_key
        request.headers['Idempotency-Key'].presence
      end

      def build_decision
        attrs = {
          team: current_team,
          hourglass_message_id: params.require(:hourglass_message_id),
          body_snapshot: params.require(:body_snapshot),
          pinned_at: params[:pinned_at] || Time.current,
          pinned_by_user: lookup_pinned_by_user,
          idempotency_key: idempotency_key
        }
        decisions_scope.new(attrs)
      end

      def lookup_pinned_by_user
        email = params[:pinned_by_email].to_s.downcase
        return nil if email.blank?

        User.find_by('LOWER(email) = ?', email)
      end

      def broadcast(action, decision)
        stream = stream_name
        case action
        when :append
          Turbo::StreamsChannel.broadcast_append_to(
            stream, target: list_target, partial: 'decisions/decision', locals: { decision: decision }
          )
        when :remove
          Turbo::StreamsChannel.broadcast_remove_to(
            stream, target: ActionView::RecordIdentifier.dom_id(decision)
          )
        end
      end

      def stream_name
        @issue ? "issue_#{@issue.id}_decisions" : "project_#{@project.id}_decisions"
      end

      def list_target
        @issue ? "issue_#{@issue.id}_decisions_list" : "project_#{@project.id}_decisions_list"
      end
    end
  end
end
