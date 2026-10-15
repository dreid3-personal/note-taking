require "test_helper"

# Fixtures: Alice and Bob are in Engineering, Carol is in Design, Dave is in no team.
# Alice wrote everything: Alice folder > Alice subfolder, the note Alice nested inside Alice folder,
# Alice private at the top level, and Eng plan inside the Engineering team folder.
# Alice private is shared with Carol for viewing, and Alice folder with Design for viewing.
class AccessResolverTest < ActiveSupport::TestCase
  # Each way access can come about, on its own

  test "the author can edit" do
    assert_access :edit, users(:alice), notes(:alice_private)
    assert_access :edit, users(:alice), folders(:empty_folder)
  end

  test "a team member can edit their team folder" do
    assert_access :edit, users(:bob), folders(:engineering)
  end

  test "everyone_access applies to every user" do
    note = notes(:alice_private)

    note.update!(everyone_access: :view)
    assert_access :view, users(:dave), note

    note.update!(everyone_access: :edit)
    assert_access :edit, users(:dave), note
  end

  test "a direct share gives its level" do
    assert_access :view, users(:carol), notes(:alice_private)

    Share.create!(note: notes(:alice_private), user: users(:dave), access: :edit)
    assert_access :edit, users(:dave), notes(:alice_private)
  end

  test "a team share gives its level to the team's members" do
    assert_access :view, users(:carol), folders(:alice_folder)

    Share.create!(note: notes(:alice_private), team: teams(:engineering), access: :edit)
    assert_access :edit, users(:bob), notes(:alice_private)
  end

  # Inherited from a parent folder, and from a grandparent folder

  test "the parent folder's author can edit what others put inside it" do
    note = Note.create!(title: "Bob's", author: users(:bob), folder: folders(:alice_folder))

    assert_access :edit, users(:alice), note
  end

  test "the grandparent folder's author can edit what others put inside it" do
    note = Note.create!(title: "Bob's", author: users(:bob), folder: folders(:alice_subfolder))
    folder = Folder.create!(name: "Bob's", author: users(:bob), parent: folders(:alice_subfolder))

    assert_access :edit, users(:alice), note
    assert_access :edit, users(:alice), folder
  end

  test "team members can edit everything in their team folder, at any depth" do
    specs = Folder.create!(name: "Specs", author: users(:alice), parent: folders(:engineering))
    deep = Note.create!(title: "Deep", author: users(:alice), folder: specs)

    assert_access :edit, users(:bob), notes(:eng_plan)
    assert_access :edit, users(:bob), specs
    assert_access :edit, users(:bob), deep
  end

  test "everyone_access is inherited from a parent and a grandparent folder" do
    deep = deep_note
    folders(:alice_folder).update!(everyone_access: :view)

    assert_access :view, users(:dave), notes(:alice_nested)
    assert_access :view, users(:dave), folders(:alice_subfolder)
    assert_access :view, users(:dave), deep
  end

  test "a direct share is inherited from a parent and a grandparent folder" do
    deep = deep_note
    Share.create!(folder: folders(:alice_folder), user: users(:dave), access: :edit)

    assert_access :edit, users(:dave), notes(:alice_nested)
    assert_access :edit, users(:dave), folders(:alice_subfolder)
    assert_access :edit, users(:dave), deep
  end

  test "a team share is inherited from a parent and a grandparent folder" do
    deep = deep_note

    assert_access :view, users(:carol), notes(:alice_nested)
    assert_access :view, users(:carol), folders(:alice_subfolder)
    assert_access :view, users(:carol), deep
  end

  test "access to a folder doesn't flow up to the folder above it" do
    Share.create!(folder: folders(:alice_subfolder), user: users(:dave), access: :edit)

    assert_access :edit, users(:dave), folders(:alice_subfolder)
    assert_access :none, users(:dave), folders(:alice_folder)
    assert_access :none, users(:dave), notes(:alice_nested)
  end

  # Combinations: the highest level wins

  test "view from a folder plus edit from the note's own share gives edit" do
    Share.create!(note: notes(:alice_nested), user: users(:carol), access: :edit)

    assert_access :edit, users(:carol), notes(:alice_nested)
  end

  test "edit from a folder plus view from the note's own share gives edit" do
    Share.create!(folder: folders(:alice_folder), user: users(:dave), access: :edit)
    Share.create!(note: notes(:alice_nested), user: users(:dave), access: :view)

    assert_access :edit, users(:dave), notes(:alice_nested)
  end

  test "a direct share and a team share on the same item give the higher one" do
    Share.create!(note: notes(:alice_private), team: teams(:design), access: :edit)

    assert_access :edit, users(:carol), notes(:alice_private)
  end

  test "everyone view plus a direct edit share gives edit" do
    notes(:alice_private).update!(everyone_access: :view)
    Share.create!(note: notes(:alice_private), user: users(:dave), access: :edit)

    assert_access :edit, users(:dave), notes(:alice_private)
    assert_access :view, users(:bob), notes(:alice_private)
  end

  # Inherited access can't be reduced

  test "a note set to everyone_access none inside a folder shared for viewing is still viewable" do
    assert notes(:alice_nested).everyone_none?

    assert_access :view, users(:carol), notes(:alice_nested)
  end

  test "a lower share on the item doesn't reduce what it inherits" do
    Share.create!(note: notes(:eng_plan), user: users(:bob), access: :view)

    assert_access :edit, users(:bob), notes(:eng_plan)
  end

  # No access at all

  test "a user with no grants has none" do
    [ notes(:alice_private), notes(:alice_nested), notes(:eng_plan),
      folders(:alice_folder), folders(:engineering), folders(:design) ].each do |item|
      assert_access :none, users(:dave), item
    end
  end

  test "a user on an unrelated team has none" do
    assert_access :none, users(:carol), folders(:engineering)
    assert_access :none, users(:carol), notes(:eng_plan)
    assert_access :none, users(:bob), folders(:design)
    assert_access :none, users(:bob), notes(:alice_nested)
  end

  test "teammates don't get each other's private items" do
    assert_access :none, users(:bob), notes(:alice_private)
    assert_access :none, users(:bob), folders(:alice_folder)
  end

  # Team membership changes

  test "joining a team grants its shares and its team folder" do
    teams(:design).memberships.create!(user: users(:dave))

    assert_access :view, users(:dave), folders(:alice_folder)
    assert_access :view, users(:dave), notes(:alice_nested)
    assert_access :edit, users(:dave), folders(:design)
  end

  test "the creator of a team gets its team folder through membership, not authorship" do
    assert_equal users(:carol), folders(:design).author
    assert_access :edit, users(:carol), folders(:design)

    memberships(:carol_design).destroy!
    assert_access :none, users(:carol), folders(:design)
  end

  test "leaving a team removes its shares and its team folder" do
    memberships(:carol_design).destroy!

    assert_access :none, users(:carol), folders(:alice_folder)
    assert_access :none, users(:carol), notes(:alice_nested)
    assert_access :none, users(:carol), folders(:design)
  end

  test "an author keeps access to their own note inside a team folder after leaving the team" do
    note = Note.create!(title: "Bob's notes", author: users(:bob), folder: folders(:engineering))
    memberships(:bob_engineering).destroy!

    assert_access :edit, users(:bob), note
    assert_access :none, users(:bob), folders(:engineering)
    assert_access :none, users(:bob), notes(:eng_plan)
  end

  # Share changes take effect immediately

  test "lowering a share from edit to view gives view" do
    share = Share.create!(note: notes(:alice_private), user: users(:dave), access: :edit)
    assert_access :edit, users(:dave), notes(:alice_private)

    share.update!(access: :view)
    assert_access :view, users(:dave), notes(:alice_private)
  end

  test "removing a share gives none" do
    shares(:alice_private_carol).destroy!

    assert_access :none, users(:carol), notes(:alice_private)
  end

  test "removing a share leaves access that another rule still grants" do
    notes(:alice_private).update!(everyone_access: :view)
    Share.create!(note: notes(:alice_private), user: users(:dave), access: :edit).destroy!

    assert_access :view, users(:dave), notes(:alice_private)
  end

  test "removing a folder's team share removes the access it gave inside" do
    shares(:alice_folder_design).destroy!

    assert_access :none, users(:carol), notes(:alice_nested)
  end

  # The API

  test "can_view? and can_edit? follow the level" do
    resolver = AccessResolver.new(users(:carol))

    assert resolver.can_view?(notes(:alice_private))
    assert_not resolver.can_edit?(notes(:alice_private))
    assert_not resolver.can_view?(notes(:eng_plan))
    assert AccessResolver.new(users(:alice)).can_edit?(notes(:alice_private))
  end

  test "only accepts notes and folders" do
    assert_raises(ArgumentError) { AccessResolver.new(users(:alice)).access_to(teams(:engineering)) }
  end

  test "resolves parents from preloaded folders without querying them again" do
    deep = deep_note
    folders = Folder.all.to_a
    resolver = AccessResolver.new(users(:carol), folders: folders)
    resolver.access_to(folders.first) # Loads Carol's teams and shares.

    assert_no_queries { assert resolver.can_view?(deep) }
  end

  # Unsaved changes

  test "unsaved changes to an item don't grant access" do
    note = notes(:alice_private)
    note.everyone_access = :edit
    assert_access :none, users(:dave), note

    note.author = users(:dave)
    assert_access :none, users(:dave), note
  end

  test "moving a note into an open folder grants nothing until it is saved" do
    Share.create!(folder: folders(:alice_folder), user: users(:dave), access: :edit)
    note = notes(:alice_private)
    note.folder = folders(:alice_folder)

    assert_access :none, users(:dave), note
    note.save!
    assert_access :edit, users(:dave), note
  end

  test "moving a folder into an open folder grants nothing until it is saved" do
    Share.create!(folder: folders(:alice_folder), user: users(:dave), access: :edit)
    folder = folders(:empty_folder)
    folder.parent = folders(:alice_folder)

    assert_access :none, users(:dave), folder
    assert_empty AccessResolver.inherited_grants(folder)
  end

  test "an unsaved item gives no access, even to its author" do
    assert_access :none, users(:alice), Note.new(title: "Draft", author: users(:alice))
    assert_access :none, users(:alice), Folder.new(name: "Draft", author: users(:alice))
  end

  # No leaks sideways or upward

  test "a share on a sibling folder doesn't leak" do
    Share.create!(folder: folders(:empty_folder), user: users(:dave), access: :edit)

    assert_access :none, users(:dave), folders(:alice_folder)
    assert_access :none, users(:dave), folders(:alice_subfolder)
    assert_access :none, users(:dave), notes(:alice_nested)
  end

  test "a share on a note doesn't leak to its folder or its sibling notes and folders" do
    sibling = Note.create!(title: "Sibling", author: users(:alice), folder: folders(:alice_folder))
    Share.create!(note: notes(:alice_nested), user: users(:dave), access: :edit)

    assert_access :edit, users(:dave), notes(:alice_nested)
    assert_access :none, users(:dave), sibling
    assert_access :none, users(:dave), folders(:alice_folder)
    assert_access :none, users(:dave), folders(:alice_subfolder)
  end

  test "a share on a child folder doesn't leak to notes beside it" do
    Share.create!(folder: folders(:alice_subfolder), user: users(:dave), access: :edit)

    assert_access :none, users(:dave), notes(:alice_nested)
  end

  # Grants inherited from parent folders, for the sharing page

  test "lists the grants a note inherits from its folder" do
    note = Note.create!(title: "Bob's", author: users(:bob), folder: folders(:alice_folder))

    assert_equal [
      [ users(:alice), "edit", folders(:alice_folder) ],
      [ teams(:design), "view", folders(:alice_folder) ]
    ], summarize(AccessResolver.inherited_grants(note))
  end

  test "leaves out the item's own author" do
    assert_equal [
      [ teams(:design), "view", folders(:alice_folder) ]
    ], summarize(AccessResolver.inherited_grants(notes(:alice_nested)))
  end

  test "lists grants from every folder above, keeping each grantee's highest level" do
    note = Note.create!(title: "Bob's", author: users(:bob), folder: folders(:alice_subfolder))
    folders(:alice_folder).update!(everyone_access: :view)
    Share.create!(folder: folders(:alice_subfolder), team: teams(:design), access: :edit)
    Share.create!(folder: folders(:alice_folder), user: users(:dave), access: :view)

    assert_equal [
      [ users(:alice), "edit", folders(:alice_subfolder) ],
      [ teams(:design), "edit", folders(:alice_subfolder) ],
      [ :everyone, "view", folders(:alice_folder) ],
      [ users(:dave), "view", folders(:alice_folder) ]
    ], summarize(AccessResolver.inherited_grants(note))
  end

  test "orders grants by the folder their highest level comes from, nearest first" do
    note = Note.create!(title: "Bob's", author: users(:bob), folder: folders(:alice_subfolder))
    Share.create!(folder: folders(:alice_subfolder), user: users(:dave), access: :view)
    Share.create!(folder: folders(:alice_subfolder), user: users(:carol), access: :edit)
    Share.create!(folder: folders(:alice_folder), user: users(:dave), access: :edit)

    assert_equal [
      [ users(:alice), "edit", folders(:alice_subfolder) ],
      [ users(:carol), "edit", folders(:alice_subfolder) ],
      [ teams(:design), "view", folders(:alice_folder) ],
      [ users(:dave), "edit", folders(:alice_folder) ]
    ], summarize(AccessResolver.inherited_grants(note))
  end

  # A folder's user and team shares sort in opposite orders in the (folder_id, user_id) and
  # (folder_id, team_id) indexes, so this fails whichever index SQLite reads them through.
  test "lists the shares from one folder in the order they were made" do
    note = Note.create!(title: "Bob's", author: users(:bob), folder: folders(:alice_subfolder))
    Share.create!(folder: folders(:alice_subfolder), user: users(:dave), access: :view)
    Share.create!(folder: folders(:alice_subfolder), team: teams(:engineering), access: :view)
    Share.create!(folder: folders(:alice_folder), user: users(:carol), access: :view)

    assert_equal [
      [ users(:alice), "edit", folders(:alice_subfolder) ],
      [ users(:dave), "view", folders(:alice_subfolder) ],
      [ teams(:engineering), "view", folders(:alice_subfolder) ],
      [ teams(:design), "view", folders(:alice_folder) ],
      [ users(:carol), "view", folders(:alice_folder) ]
    ], summarize(AccessResolver.inherited_grants(note))
  end

  test "a folder inherits grants from its own parents, not itself" do
    folder = Folder.create!(name: "Bob's", author: users(:bob), parent: folders(:alice_folder))
    Share.create!(folder: folder, user: users(:dave), access: :edit)

    assert_equal [
      [ users(:alice), "edit", folders(:alice_folder) ],
      [ teams(:design), "view", folders(:alice_folder) ]
    ], summarize(AccessResolver.inherited_grants(folder))
  end

  test "lists the team of a team folder, not the folder's author" do
    note = Note.create!(title: "Bob's", author: users(:bob), folder: folders(:engineering))

    assert_equal [
      [ teams(:engineering), "edit", folders(:engineering) ]
    ], summarize(AccessResolver.inherited_grants(note))
  end

  test "a top-level item inherits nothing, and its own shares aren't listed" do
    assert_empty AccessResolver.inherited_grants(notes(:alice_private))
    assert_empty AccessResolver.inherited_grants(folders(:alice_folder))
  end

  private
    def assert_access(expected, user, item)
      actual = AccessResolver.new(user).access_to(item)
      assert_equal AccessLevel[expected], actual,
        "expected #{user.name} to have #{expected} access to #{item.class.name} #{item.try(:title) || item.name}, got #{actual}"
    end

    # A note inside Alice subfolder, so Alice folder is its grandparent.
    def deep_note
      Note.create!(title: "Deep", author: users(:alice), folder: folders(:alice_subfolder))
    end

    def summarize(grants)
      grants.map { |grant| [ grant.grantee, grant.level.to_s, grant.folder ] }
    end
end
