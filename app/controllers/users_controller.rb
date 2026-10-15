# The Users page works without a current user, so the first user can be added.
class UsersController < ApplicationController
  def index
    @users = User.order(:name)
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to users_path, notice: "User added."
    else
      @users = User.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  private
    def user_params
      params.expect(user: [ :name, :email ])
    end
end
