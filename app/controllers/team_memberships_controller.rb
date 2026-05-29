class TeamMembershipsController < ApplicationController
  before_action :set_team
  before_action :require_admin, only: %i[promote demote]
  before_action :require_owner, only: %i[transfer_ownership]
  before_action :set_membership, only: %i[promote demote]

  def promote
    if @team.owner?(@membership.user)
      redirect_back fallback_location: team_team_invitations_path(@team),
                    alert: 'Owner is already an admin.'
      return
    end

    @membership.admin!
    redirect_back fallback_location: team_team_invitations_path(@team),
                  notice: "#{@membership.user.name} is now an admin."
  end

  def demote
    if @team.owner?(@membership.user)
      redirect_back fallback_location: team_team_invitations_path(@team),
                    alert: 'Cannot demote the team owner.'
      return
    end

    @membership.member!
    redirect_back fallback_location: team_team_invitations_path(@team),
                  notice: "#{@membership.user.name} is no longer an admin."
  end

  def transfer_ownership
    new_owner = @team.users.find_by(id: params[:user_id])
    if new_owner.nil?
      redirect_back fallback_location: team_team_invitations_path(@team),
                    alert: 'Selected user is not a member of this team.'
      return
    end

    previous_owner = @team.owner
    Team.transaction do
      @team.team_memberships.find_or_create_by!(user: new_owner).update!(role: :admin)
      @team.update!(owner: new_owner)
      @team.team_memberships.find_or_create_by!(user: previous_owner).update!(role: :admin) if previous_owner
    end

    redirect_back fallback_location: team_team_invitations_path(@team),
                  notice: "Ownership transferred to #{new_owner.name}."
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_membership
    @membership = @team.team_memberships.find_by!(user_id: params[:user_id])
  end

  def require_admin
    require_team_admin!(@team)
  end

  def require_owner
    require_team_owner!(@team)
  end
end
