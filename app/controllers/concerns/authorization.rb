# Checks what the current user may do with a note or folder, following "Permissions" and
# "Denied access" in HIGHLEVEL_DESIGN.md. Effective access comes from AccessResolver; this concern
# only maps actions onto it and decides how a refusal looks:
#
# - no access at all: a 404, exactly like a record that doesn't exist;
# - some access, but not enough: a redirect to the item with "You don't have permission to do that."
#
#   before_action -> { require_access!(@note, :view) }, only: :show
#   before_action -> { require_access!(@folder, :rename) }, only: %i[edit update]
#   before_action -> { require_author!(@folder) }, only: :destroy
#
# Views ask the same questions with allowed_to?, so a button shows only when its action is allowed.
module Authorization
  extend ActiveSupport::Concern

  NOT_ALLOWED = "You don't have permission to do that.".freeze

  included do
    helper_method :allowed_to?
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  end

  private
    # Whether the current user may do `action` with the item:
    #
    # - :view    view it, or a folder's contents;
    # - :edit    edit a note, or create a note or folder inside a folder;
    # - :rename  rename a folder (edit access, but never a team folder);
    # - :author  share or delete it (its author only, and never a team folder).
    #
    # Nothing is allowed without a current user.
    def allowed_to?(action, item)
      return false unless current_user

      case action
      when :view then access_resolver.can_view?(item)
      when :edit then access_resolver.can_edit?(item)
      when :rename then access_resolver.can_edit?(item) && !team_folder?(item)
      when :author then item.author_id_in_database == current_user.id && !team_folder?(item)
      else raise ArgumentError, "unknown action: #{action.inspect}"
      end
    end

    # Renders a 404 or redirects unless the current user may do `action` (see allowed_to?) with
    # the item. Called from a before_action, a refusal stops the request.
    def require_access!(item, action)
      return render_not_found unless item.is_a?(Note) || item.is_a?(Folder)
      return if allowed_to?(action, item)

      if current_user && access_resolver.can_view?(item)
        redirect_to item, alert: NOT_ALLOWED, status: :see_other
      else
        render_not_found
      end
    end

    def require_author!(item)
      require_access!(item, :author)
    end

    # One resolver per request, so the user's teams and shares are loaded once.
    def access_resolver
      @access_resolver ||= AccessResolver.new(current_user)
    end

    def team_folder?(item)
      item.is_a?(Folder) && item.team_folder?
    end

    def render_not_found
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end
end
