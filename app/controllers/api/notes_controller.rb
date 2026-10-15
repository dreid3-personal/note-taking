class Api::NotesController < Api::BaseController
  STALE = "This note was changed by someone else.".freeze

  before_action -> { @note = find_record(Note, params[:id]) }, only: %i[show update destroy]
  before_action -> { require_access!(@note, :view) }, only: :show
  # Editing needs edit access; changing everyone_access is for the author.
  before_action -> { require_access!(@note, params.key?(:everyone_access) ? :author : :edit) }, only: :update
  before_action -> { require_author!(@note) }, only: :destroy
  # A new note goes inside a folder the user can edit, or at the top level.
  before_action :set_folder, only: :create
  before_action -> { require_access!(@folder, :edit) if @folder }, only: :create

  # Every note the current user can open, alphabetical.
  def index
    resolver = AccessResolver.new(current_user, folders: Folder.all.to_a)
    notes = Note.includes(:author).select { |note| resolver.can_view?(note) }
    render json: NotesHome.sort(notes).map { |note| item_json(note) }
  end

  def show
    render json: note_json(@note)
  end

  # Whoever creates a note is its author, even inside someone else's folder.
  def create
    note = Note.new(text_params(:title, :body).merge(folder: @folder, author: current_user))

    if note.save
      render json: note_json(note), status: :created, location: api_note_url(note)
    else
      render_errors(note)
    end
  end

  # Changes only the fields sent: title, body and everyone_access. The request must send the
  # lock_version it read, so saving over someone else's newer edit fails with a 409 instead of
  # overwriting it. Without one there is nothing to check against, so that is a 409 too.
  def update
    changes = text_params(:title, :body).merge(scalar_params(:everyone_access, :lock_version))
    lock_version = changes[:lock_version]
    return render json: { error: "Send the note's current lock_version." }, status: :conflict if lock_version.blank?
    raise BadRequest unless lock_version.is_a?(Integer) || lock_version.to_s.match?(/\A\d+\z/)

    if @note.update(changes)
      render json: note_json(@note)
    else
      render_errors(@note)
    end
  rescue ActiveRecord::StaleObjectError
    render json: { error: STALE }, status: :conflict
  end

  def destroy
    @note.destroy!
    head :no_content
  end

  private
    def set_folder
      folder_id = scalar_params(:folder_id)[:folder_id]
      @folder = find_record(Folder, folder_id) unless folder_id.nil? || folder_id == ""
    end

    # A null body is saved as an empty one (the column can't be null); a null title fails validation.
    def text_params(*keys)
      scalar_params(*keys).tap { |sent| sent[:body] = sent[:body].to_s if sent.key?(:body) }
    end

    def note_json(note)
      item_json(note).merge(body: note.body, body_html: MarkdownRenderer.render(note.body).to_str,
        lock_version: note.lock_version, access: access_resolver.access_to(note).to_s)
    end
end
