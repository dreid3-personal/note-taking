# Any user can see and manage any team, as on the HTML Teams pages. The creator becomes a member.
class Api::TeamsController < Api::BaseController
  def index
    render json: Team.order(:name, :id).map { |team| team_json(team) }
  end

  def show
    render json: team_json(find_record(Team, params[:id]), members: true)
  end

  def create
    team = Team.create_with_folder(name: scalar_params(:name)[:name], creator: current_user)

    if team.persisted?
      render json: team_json(team, members: true), status: :created, location: api_team_url(team)
    else
      render_errors(team)
    end
  end

  # Renaming the team renames its team folder too (see Team#rename_folder).
  def update
    team = find_record(Team, params[:id])

    if team.update(scalar_params(:name))
      render json: team_json(team, members: true)
    else
      render_errors(team)
    end
  end

  private
    def team_json(team, members: false)
      json = { id: team.id, name: team.name }
      json[:members] = team.users.order(:name, :id).map { |user| user_json(user) } if members
      json
    end
end
