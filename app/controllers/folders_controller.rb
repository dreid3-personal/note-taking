class FoldersController < ApplicationController
  before_action :require_current_user
  before_action :set_folder, only: %i[show edit update destroy]
  before_action -> { require_access!(@folder, :view) }, only: :show
  before_action -> { require_access!(@folder, :rename) }, only: %i[edit update]
  before_action -> { require_author!(@folder) }, only: :destroy
  # A new folder goes inside a folder the user can edit, or at the top level.
  before_action :set_parent, only: %i[new create]
  before_action -> { require_access!(@parent, :edit) if @parent }, only: %i[new create]

  def show
    @breadcrumbs = Breadcrumbs.new(@folder, user: current_user, resolver: access_resolver)
    @items = NotesHome.sort(@folder.subfolders.includes(:author, :team) + @folder.notes.includes(:author))
  end

  def new
    @folder = Folder.new(parent: @parent)
  end

  # Whoever creates a folder is its author, even inside someone else's folder.
  def create
    @folder = Folder.new(name: folder_params[:name], parent: @parent, author: current_user)

    if @folder.save
      redirect_to @folder, notice: "Folder created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @folder.update(name: folder_params[:name])
      redirect_to @folder, notice: "Folder renamed."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # The model refuses to delete a folder that still has contents.
  def destroy
    if @folder.destroy
      parent = @folder.parent if @folder.parent && allowed_to?(:view, @folder.parent)
      redirect_to parent || root_path, notice: "Folder deleted.", status: :see_other
    else
      redirect_to @folder, alert: @folder.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def set_folder
      @folder = Folder.find(params[:id])
    end

    def set_parent
      parent_id = action_name == "new" ? params[:parent_id] : params.dig(:folder, :parent_id)
      @parent = Folder.find(parent_id) if parent_id.present?
    end

    def folder_params
      params.expect(folder: [ :name, :parent_id ])
    end
end
