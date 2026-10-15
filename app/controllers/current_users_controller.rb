# The sidebar's "You are" switcher. There are no passwords: picking a user makes them the current user.
class CurrentUsersController < ApplicationController
  def update
    user = User.find_by(id: params[:user_id])

    if user
      session[:user_id] = user.id
    else
      session.delete(:user_id)
    end

    redirect_back_or_to root_path, status: :see_other
  end
end
