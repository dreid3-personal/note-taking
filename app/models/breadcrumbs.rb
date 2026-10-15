# The trail above a note or folder page, following "Breadcrumbs" in UI_DESIGN.md:
#
#   Notes › My notes › Alice folder › Specs
#
# It starts where the item is reached from the Notes page: the highest folder above it that the user
# can open, or the item itself when they can't open its folder. That top item's section on the Notes
# page (see NotesHome) comes next, then the folders from there down. A folder's trail ends with the
# folder itself; a note's ends with the folder it is in.
#
#   crumbs = Breadcrumbs.new(note, user: current_user, resolver: AccessResolver.new(current_user))
#   crumbs.section   # => :shared_with_me
#   crumbs.folders   # => [ folder, subfolder ]
class Breadcrumbs
  attr_reader :section, :folders

  def initialize(item, user:, resolver:)
    nearest_first = item.is_a?(Folder) ? [ item, *item.ancestors ] : [ *item.folder&.then { |folder| [ folder, *folder.ancestors ] } ]
    # Access to a folder covers everything inside it, so the folders the user can open are the
    # nearest ones, up to the first they can't.
    @folders = nearest_first.take_while { |folder| resolver.can_view?(folder) }.reverse
    @section = NotesHome.section_for(@folders.first || item, user)
  end
end
