class ApiTokensController < ApplicationController
  def index
    @api_token = Current.user.api_tokens.active.first
    @new_token_value = flash[:new_token_value]
  end

  def create
    token = ApiToken.generate_for(Current.user)
    redirect_to api_tokens_path, flash: { new_token_value: token.raw_token },
                                 notice: 'API token generated. Copy it now — it won\'t be shown again.'
  end

  def destroy
    token = Current.user.api_tokens.active.find(params[:id])
    token.revoke!
    redirect_to api_tokens_path, notice: 'API token revoked.'
  end
end
