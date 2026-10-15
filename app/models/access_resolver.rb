# Works out a user's effective access to notes and folders, following "Effective access" in
# HIGHLEVEL_DESIGN.md: the highest of these, for the item itself and every folder above it:
#
# 1. edit, if the user is the author (except of a team folder, see rule 2);
# 2. edit, if it is the team folder of a team the user belongs to;
# 3. the item's everyone_access;
# 4. the share for the user directly;
# 5. the shares for any team the user belongs to.
#
#   resolver = AccessResolver.new(current_user)
#   resolver.access_to(note)   # => an AccessLevel
#   resolver.can_view?(note)
#   resolver.can_edit?(folder)
#
# A resolver loads the user's teams and shares once and remembers each folder's access, so make a
# new one for each request: changes made after the first check aren't seen.
class AccessResolver
  # Access that an item gets from a folder above it: the grantee (a User, a Team, or :everyone)
  # has `level` through `folder`.
  Grant = Data.define(:grantee, :level, :folder)

  # Pass `folders:` to resolve parent folders from records already loaded, instead of one query
  # per folder.
  def initialize(user, folders: nil)
    @user = user
    @folders = folders&.index_by(&:id) || {}
    @folder_access = {}
  end

  def access_to(item)
    case item
    when Note then AccessLevel.highest([ own_access(item), folder_access(item.folder_id) ])
    when Folder then folder_access(item.id, item)
    else raise ArgumentError, "expected a Note or Folder, got #{item.class}"
    end
  end

  def can_view?(item)
    access_to(item).view?
  end

  def can_edit?(item)
    access_to(item).edit?
  end

  # Who gets access to the item from the folders above it, nearest folder first: each folder's
  # author (or, for a team folder, its team), everyone_access, and shares. Each grantee is listed once,
  # at the highest level they inherit (from the nearest folder that gives it). The item's own
  # author and sharing settings are not included. Used by the sharing page.
  def self.inherited_grants(item)
    folders = item.is_a?(Note) ? [ item.folder, *item.folder&.ancestors ].compact : item.ancestors
    shares = Share.where(folder_id: folders.map(&:id)).includes(:user, :team).group_by(&:folder_id)

    grants = folders.flat_map do |folder|
      [
        Grant.new(folder.team_folder? ? folder.team : folder.author, AccessLevel::EDIT, folder),
        (Grant.new(:everyone, AccessLevel[folder.everyone_access], folder) unless folder.everyone_none?),
        *shares.fetch(folder.id, []).map { |share| Grant.new(share.grantee, AccessLevel[share.access], folder) }
      ].compact
    end

    grants.group_by(&:grantee).values.map do |same_grantee|
      highest = AccessLevel.highest(same_grantee.map(&:level))
      same_grantee.find { |grant| grant.level == highest }
    end
  end

  private
    attr_reader :user

    # Access from the item itself, ignoring the folders above it.
    def own_access(item)
      levels = [ item.everyone_access, *shared_levels[[ item.class.name, item.id ]] ]
      levels << AccessLevel::EDIT if edits_as_author_or_member?(item)
      AccessLevel.highest(levels)
    end

    # A team folder's access comes only from membership: its author is just whoever created the
    # team, and loses access on leaving it like anyone else.
    def edits_as_author_or_member?(item)
      if item.is_a?(Folder) && item.team_folder?
        team_ids.include?(item.team_id)
      else
        item.author_id == user.id
      end
    end

    # A folder's access, including what it inherits, remembered by id. Walks up parent_id.
    def folder_access(folder_id, folder = nil)
      return AccessLevel::NONE if folder_id.nil?

      @folder_access.fetch(folder_id) do
        folder ||= find_folder(folder_id)
        @folder_access[folder_id] = AccessLevel.highest([ own_access(folder), folder_access(folder.parent_id) ])
      end
    end

    def find_folder(id)
      @folders[id] ||= Folder.find(id)
    end

    def team_ids
      @team_ids ||= user.memberships.pluck(:team_id).to_set
    end

    # The levels shared with the user or their teams, by [item type, item id].
    def shared_levels
      @shared_levels ||= Share.where(user_id: user.id).or(Share.where(team_id: team_ids.to_a))
        .pluck(:note_id, :folder_id, :access)
        .group_by { |note_id, folder_id, _| note_id ? [ "Note", note_id ] : [ "Folder", folder_id ] }
        .transform_values { |rows| rows.map(&:last) }
    end
end
