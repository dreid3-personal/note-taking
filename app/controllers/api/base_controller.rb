# The JSON REST API, next to the HTML pages (see API.md). No sessions, cookies, CSRF or views.
#
# The current user comes from the X-User-Id header: there are no passwords, so this is for local
# use only, like the HTML "You are" switcher. Permissions go through the same Authorization concern
# as the HTML pages; only the responses differ:
#
# - 401 {"error": ...} without a current user;
# - 404 {"error": "Not found"} for no access, identical to a record that doesn't exist;
# - 403 {"error": "You don't have permission to do that."} for too little access;
# - 400 {"error": "Bad request"} for malformed JSON, a missing required param, or a param that
#   should be a single value but isn't (an array or an object);
# - 422 {"errors": {"field": [...]}} for validation failures.
#
# Ids in a path or a body that aren't a single whole number are treated as ids that don't exist,
# so a crafted id can't tell a hidden record from a missing one.
class Api::BaseController < ActionController::API
  include Authorization

  class BadRequest < StandardError; end

  wrap_parameters false

  # ActiveModel::RangeError: a number too big for its column, such as a 23-digit lock_version.
  rescue_from BadRequest, ActionController::ParameterMissing, ActionDispatch::Http::Parameters::ParseError,
    ActiveModel::RangeError do
    render json: { error: "Bad request" }, status: :bad_request
  end

  before_action :require_current_user

  private
    # The user named by the X-User-Id header, if it is a single id of a user that exists.
    def current_user
      return @current_user if defined?(@current_user)

      id = request.headers["X-User-Id"].to_s
      @current_user = (User.find_by(id: id) if id.match?(/\A\d+\z/))
    end

    def require_current_user
      return if current_user

      render json: { error: "Send the X-User-Id header with the id of an existing user." }, status: :unauthorized
    end

    def render_not_found
      render json: { error: "Not found" }, status: :not_found
    end

    def render_not_allowed(_item)
      render json: { error: NOT_ALLOWED }, status: :forbidden
    end

    def render_errors(record)
      render json: { errors: record.errors.to_hash }, status: :unprocessable_entity
    end

    # Finds a record by an id from the path or the body. Anything but one whole number is not found.
    def find_record(model, id)
      raise ActiveRecord::RecordNotFound unless id.is_a?(Integer) || (id.is_a?(String) && id.match?(/\A\d+\z/))

      model.find(id)
    end

    # The given body params that were sent, as a Hash. Each must be a single value (a string,
    # number, boolean or null), or the request is a 400.
    def scalar_params(*keys)
      keys.select { |key| params.key?(key) }.to_h do |key|
        value = params[key]
        raise BadRequest unless value.nil? || value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false

        [ key, value ]
      end
    end

    # The id of a note's or folder's parent folder, only if the current user can open it, so an
    # item shared on its own doesn't reveal the hidden folder it sits in.
    def visible_folder_id(folder_id)
      return if folder_id.nil?

      @visible_folder_ids ||= {}
      @visible_folder_ids.fetch(folder_id) do
        @visible_folder_ids[folder_id] = (folder_id if allowed_to?(:view, Folder.find(folder_id)))
      end
    end

    def user_json(user)
      { id: user.id, name: user.name, email: user.email }
    end

    def author_json(item)
      { id: item.author.id, name: item.author.name }
    end

    # A note or folder in a list: the home page sections, a folder's children, the index pages.
    def item_json(item)
      if item.is_a?(Folder)
        { type: "folder", id: item.id, name: item.name, parent_id: visible_folder_id(item.parent_id),
          team_id: item.team_id, author: author_json(item) }
      else
        { type: "note", id: item.id, title: item.title, folder_id: visible_folder_id(item.folder_id),
          author: author_json(item), updated_at: item.updated_at }
      end
    end
end
