class ProfilesController < ApplicationController
  def update
    if current_user.update(avatar_color: params[:avatar_color])
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: root_path }
      end
    else
      head :unprocessable_entity
    end
  end
end
