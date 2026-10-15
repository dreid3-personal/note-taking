class NotesController < ApplicationController
  STALE = "This note was changed by someone else.".freeze

  before_action :require_current_user, except: :index
  before_action :set_note, only: %i[show edit update destroy]
  before_action -> { require_access!(@note, :view) }, only: :show
  before_action -> { require_access!(@note, :edit) }, only: %i[edit update]
  before_action -> { require_author!(@note) }, only: :destroy
  # A new note goes inside a folder the user can edit, or at the top level.
  before_action :set_folder, only: %i[new create]
  before_action -> { require_access!(@folder, :edit) if @folder }, only: %i[new create]

  # The Notes page: the current user's top level, or the "Pick a user" message.
  def index
    if current_user
      @home = NotesHome.new(current_user)
    else
      @no_users = !User.exists?
    end
  end

  def show
    @breadcrumbs = Breadcrumbs.new(@note, user: current_user, resolver: access_resolver)
    @body_html = MarkdownRenderer.render(@note.body)
  end

  def new
    @note = Note.new(folder: @folder)
  end

  # Whoever creates a note is its author, even inside someone else's folder.
  def create
    @note = Note.new(note_params.slice(:title, :body).merge(folder: @folder, author: current_user))

    if @note.save
      redirect_to @note, notice: "Note created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # The form sends back the lock_version it was opened with, so saving over someone else's newer
  # edit fails instead of overwriting it. The form then keeps what was typed, along with the old
  # lock_version, so submitting it again fails too. Without a lock_version there is nothing to
  # check against, so the request is refused as a bad request.
  def update
    lock_version = note_params.require(:lock_version)

    if @note.update(note_params.slice(:title, :body).merge(lock_version: lock_version))
      redirect_to @note, notice: "Note saved."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    flash.now[:alert] = STALE
    render :edit, status: :conflict
  end

  def destroy
    @note.destroy!
    folder = @note.folder if @note.folder && allowed_to?(:view, @note.folder)
    redirect_to folder || root_path, notice: "Note deleted.", status: :see_other
  end

  private
    def set_note
      @note = Note.find(params[:id])
    end

    # The folder comes from ?folder_id= on the new page and note[folder_id] on create. Anything
    # but a single id, such as an array, is treated as an id that doesn't exist: a 404, whether or
    # not the folder is there. (require_access! would also 404 on the Array that Folder.find
    # returns for one, but the check belongs here, where the param is read.)
    def set_folder
      folder_id = action_name == "new" ? params[:folder_id] : note_params && params[:note][:folder_id]
      raise ActiveRecord::RecordNotFound unless folder_id.nil? || folder_id.is_a?(String)

      @folder = Folder.find(folder_id) if folder_id.present?
    end

    def note_params
      params.expect(note: [ :title, :body, :folder_id, :lock_version ])
    end
end
