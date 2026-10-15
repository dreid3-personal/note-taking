# Adds users to a team and removes them, from the team page.
class MembershipsController < ApplicationController
  before_action :require_current_user
  before_action :set_team

  def create
    membership = @team.memberships.new(user: User.find_by(id: params[:user_id]))

    if membership.save
      redirect_to @team, notice: "#{membership.user.name} added.", status: :see_other
    else
      redirect_to @team, alert: membership.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    membership = @team.memberships.find(params[:id])
    membership.destroy!
    redirect_to @team, notice: "#{membership.user.name} removed.", status: :see_other
  end

  private
    def set_team
      @team = Team.find(params[:team_id])
    end
end
