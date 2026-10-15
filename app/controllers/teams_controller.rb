# Any user can manage any team, but there must be a current user: they become a new team's creator.
class TeamsController < ApplicationController
  before_action :require_current_user
  before_action :set_team, only: [ :show, :edit, :update ]

  def index
    @teams = teams_with_member_counts
    @team = Team.new
  end

  def show
    @memberships = @team.memberships.eager_load(:user).merge(User.order(:name))
    @addable_users = User.where.not(id: @team.memberships.select(:user_id)).order(:name)
  end

  def create
    @team = Team.create_with_folder(name: team_params[:name], creator: current_user)

    if @team.persisted?
      redirect_to @team, notice: "Team added.", status: :see_other
    else
      @teams = teams_with_member_counts
      render :index, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Renaming the team renames its team folder too (see Team#rename_folder).
  def update
    if @team.update(team_params)
      redirect_to @team, notice: "Team renamed.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_team
      @team = Team.find(params[:id])
    end

    def team_params
      params.expect(team: [ :name ])
    end

    def teams_with_member_counts
      Team.left_joins(:memberships).group(:id).select("teams.*, COUNT(memberships.id) AS members_count").order(:name)
    end
end
