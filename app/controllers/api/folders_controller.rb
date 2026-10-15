class Api::FoldersController < Api::BaseController
  before_action -> { @folder = find_record(Folder, params[:id]) }, only: %i[show update destroy]
  before_action -> { require_access!(@folder, :view) }, only: :show
  # Renaming needs edit access (never a team folder); changing everyone_access is for the author.
  before_action -> { require_access!(@folder, params.key?(:everyone_access) ? :author : :rename) }, only: :update
  before_action -> { require_author!(@folder) }, only: :destroy
  # A new folder goes inside a folder the user can edit, or at the top level.
  before_action :set_parent, only: :create
  before_action -> { require_access!(@parent, :edit) if @parent }, only: :create

  # Every folder the current user can open, alphabetical.
  def index
    folders = Folder.includes(:author).to_a
    resolver = AccessResolver.new(current_user, folders: folders)
    render json: NotesHome.sort(folders.select { |folder| resolver.can_view?(folder) }).map { |folder| item_json(folder) }
  end

  def show
    render json: folder_json(@folder)
  end

  # Whoever creates a folder is its author, even inside someone else's folder.
  def create
    folder = Folder.new(name: scalar_params(:name)[:name], parent: @parent, author: current_user)

    if folder.save
      render json: folder_json(folder), status: :created, location: api_folder_url(folder)
    else
      render_errors(folder)
    end
  end

  # Changes only the fields sent: name and everyone_access.
  def update
    if @folder.update(scalar_params(:name, :everyone_access))
      render json: folder_json(@folder)
    else
      render_errors(@folder)
    end
  end

  # The model refuses to delete a folder that still has contents.
  def destroy
    if @folder.destroy
      head :no_content
    else
      render_errors(@folder)
    end
  end

  private
    def set_parent
      parent_id = scalar_params(:parent_id)[:parent_id]
      @parent = find_record(Folder, parent_id) unless parent_id.nil? || parent_id == ""
    end

    # The folder with its children: subfolders first, then notes, each alphabetical.
    def folder_json(folder)
      children = NotesHome.sort(folder.subfolders.includes(:author) + folder.notes.includes(:author))
      item_json(folder).merge(access: access_resolver.access_to(folder).to_s, children: children.map { |item| item_json(item) })
    end
end
