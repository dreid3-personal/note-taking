class NotesController < ApplicationController
  # A placeholder for the Notes page. It only shows the "Pick a user" message for now.
  def index
    @no_users = !User.exists? unless current_user
  end
end
