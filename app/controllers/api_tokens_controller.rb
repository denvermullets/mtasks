class ApiTokensController < ApplicationController
  def index
    @api_tokens = Current.user.api_tokens.active.order(created_at: :desc)
    @new_token_value = flash[:new_token_value]
  end

  def new
    @api_token = ApiToken.new(scopes: ApiToken::AVAILABLE_SCOPES)
    @teams = Current.user.teams.not_archived.order(:name)
  end

  def create
    name = params.dig(:api_token, :name).to_s.strip
    if name.blank?
      redirect_to new_api_token_path, alert: 'Name is required.'
      return
    end

    team = resolve_team(params.dig(:api_token, :team_id))
    scopes = scopes_for(params.dig(:api_token, :permission))

    token = ApiToken.generate_for(Current.user, name: name, team: team, scopes: scopes)
    redirect_to api_tokens_path, flash: { new_token_value: token.raw_token },
                                 notice: "API token '#{token.name}' generated. Copy it now — it won't be shown again."
  end

  def destroy
    token = Current.user.api_tokens.active.find(params[:id])
    token.revoke!
    redirect_to api_tokens_path, notice: 'API token revoked.'
  end

  private

  def resolve_team(team_id)
    return nil if team_id.blank?

    Current.user.teams.not_archived.find_by(id: team_id)
  end

  def scopes_for(permission)
    case permission.to_s
    when 'read' then %w[read]
    else %w[read write]
    end
  end
end
