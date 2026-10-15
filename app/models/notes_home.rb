# The top level of the Notes page for one user, following "Top level" in UI_DESIGN.md.
#
# It lists every item the user can access whose parent folder they can't open (or that has no
# parent), so each item appears exactly once: everything else is reached by opening folders.
# The items are split into three sections, each with folders first and then notes, alphabetical:
#
# - my_notes:       the user's own items;
# - team_folders:   the folders of the user's teams;
# - shared_with_me: items other people own.
class NotesHome
  attr_reader :my_notes, :team_folders, :shared_with_me

  def initialize(user)
    folders = Folder.includes(:author).to_a
    resolver = AccessResolver.new(user, folders: folders)

    open_folder_ids = folders.select { |folder| resolver.can_view?(folder) }.map(&:id)
    # Notes inside a folder the user can open are listed in that folder, so skip loading them.
    notes = Note.where(folder_id: nil).or(Note.where.not(folder_id: open_folder_ids)).includes(:author)

    items = (folders + notes).select do |item|
      parent_id = item.is_a?(Note) ? item.folder_id : item.parent_id
      resolver.can_view?(item) && !open_folder_ids.include?(parent_id)
    end

    team_ids = user.memberships.pluck(:team_id)
    sections = items.sort_by { |item| sort_key(item) }.group_by do |item|
      if item.is_a?(Folder) && team_ids.include?(item.team_id) then :team_folders
      elsif item.author_id == user.id then :my_notes
      else :shared_with_me
      end
    end

    @my_notes = sections.fetch(:my_notes, [])
    @team_folders = sections.fetch(:team_folders, [])
    @shared_with_me = sections.fetch(:shared_with_me, [])
  end

  private
    def sort_key(item)
      item.is_a?(Folder) ? [ 0, item.name.downcase, item.id ] : [ 1, item.title.downcase, item.id ]
    end
end
