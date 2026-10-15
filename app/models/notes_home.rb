# The top level of the Notes page for one user, following "Top level" in UI_DESIGN.md.
#
# It lists every item the user can access whose parent folder they can't open (or that has no
# parent), so each item appears exactly once: everything else is reached by opening folders.
# The items are split into three sections, each with folders first and then notes, alphabetical:
#
# - my_notes:       the user's own items;
# - team_folders:   the folders of the user's teams;
# - shared_with_me: items other people own.
#
# It loads every folder, and every note that isn't inside a folder the user can open, on purpose:
# the app runs locally with a handful of users, and deciding access in Ruby keeps the rules in
# AccessResolver. If that gets slow, move the ancestor walk into SQL (WITH RECURSIVE).
class NotesHome
  SECTIONS = { my_notes: "My notes", team_folders: "Team folders", shared_with_me: "Shared with me" }.freeze

  attr_reader :my_notes, :team_folders, :shared_with_me

  # The section a top-level item belongs in. A team folder can only be opened through membership,
  # so any listed one is the user's team's.
  def self.section_for(item, user)
    if item.is_a?(Folder) && item.team_folder? then :team_folders
    elsif item.author_id == user.id then :my_notes
    else :shared_with_me
    end
  end

  # Folders first, then notes, each alphabetical. Folder pages list their contents the same way.
  def self.sort(items)
    items.sort_by do |item|
      item.is_a?(Folder) ? [ 0, item.name.downcase, item.id ] : [ 1, item.title.downcase, item.id ]
    end
  end

  def initialize(user)
    folders = Folder.includes(:author).to_a
    resolver = AccessResolver.new(user, folders: folders)

    open_folder_ids = folders.select { |folder| resolver.can_view?(folder) }.map(&:id).to_set
    # Notes inside a folder the user can open are listed in that folder, so skip loading them.
    notes = Note.where(folder_id: nil).or(Note.where.not(folder_id: open_folder_ids.to_a)).includes(:author)

    items = (folders + notes).select do |item|
      parent_id = item.is_a?(Note) ? item.folder_id : item.parent_id
      resolver.can_view?(item) && !open_folder_ids.include?(parent_id)
    end

    sections = self.class.sort(items).group_by { |item| self.class.section_for(item, user) }

    @my_notes = sections.fetch(:my_notes, [])
    @team_folders = sections.fetch(:team_folders, [])
    @shared_with_me = sections.fetch(:shared_with_me, [])
  end
end
