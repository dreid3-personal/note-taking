# Listing and adding users works without a current user, so the first user can be created.
class Api::UsersController < Api::BaseController
  skip_before_action :require_current_user, only: %i[index create]

  def index
    render json: User.order(:name, :id).map { |user| user_json(user) }
  end

  def show
    render json: user_json(find_record(User, params[:id]))
  end

  def create
    user = User.new(scalar_params(:name, :email))

    if user.save
      render json: user_json(user), status: :created, location: api_user_url(user)
    else
      render_errors(user)
    end
  rescue ActiveRecord::RecordNotUnique
    # Two quick requests can both pass the uniqueness validation; the unique index stops the second.
    render json: { errors: { email: [ "has already been taken" ] } }, status: :unprocessable_entity
  end
end
