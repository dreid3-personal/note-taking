# Adds users to a team and removes them. Any user may do this, as on the HTML team page.
class Api::MembersController < Api::BaseController
  before_action -> { @team = find_record(Team, params[:team_id]) }

  def create
    user_id = scalar_params(:user_id)[:user_id]
    membership = @team.memberships.new(user: (User.find_by(id: user_id) if user_id.to_s.match?(/\A\d+\z/)))

    if membership.save
      render json: user_json(membership.user), status: :created, location: api_team_url(@team)
    else
      render_errors(membership)
    end
  rescue ActiveRecord::RecordNotUnique
    render json: { errors: { user_id: [ "is already a member of this team" ] } }, status: :unprocessable_entity
  end

  def destroy
    membership = @team.memberships.find_by!(user: find_record(User, params[:user_id]))
    membership.destroy!
    head :no_content
  end
end
