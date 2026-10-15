class NotesController < ApplicationController
  before_action :require_current_user, except: :index
  before_action :set_note, only: :show
  before_action -> { require_access!(@note, :view) }, only: :show

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

  private
    def set_note
      @note = Note.find(params[:id])
    end
end
