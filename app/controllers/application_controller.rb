class ApplicationController < ActionController::Base
  include Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user

  private
    # The user picked in the sidebar's "You are" switcher. A stale id, such as one left over from
    # before a database reset, is cleared from the session.
    def current_user
      return @current_user if defined?(@current_user)

      @current_user = User.find_by(id: session[:user_id]) if session[:user_id]
      session.delete(:user_id) if session[:user_id] && @current_user.nil?
      @current_user
    end

    # Use as a before_action on pages that need a current user. Sends the visitor to the Notes page,
    # which asks them to pick one.
    def require_current_user
      redirect_to root_path, status: :see_other unless current_user
    end
end
