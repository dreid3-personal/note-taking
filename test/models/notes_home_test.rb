require "test_helper"

# Fixtures: see access_resolver_test.rb.
class NotesHomeTest < ActiveSupport::TestCase
  test "Alice sees her own top-level items and her team folder" do
    home = NotesHome.new(users(:alice))

    assert_equal [ folders(:alice_folder), folders(:empty_folder), notes(:alice_private) ], home.my_notes
    assert_equal [ folders(:engineering) ], home.team_folders
    assert_empty home.shared_with_me
  end

  test "a team member sees the team folder, even though someone else created it" do
    home = NotesHome.new(users(:bob))

    assert_empty home.my_notes
    assert_equal [ folders(:engineering) ], home.team_folders
    assert_empty home.shared_with_me
  end

  test "items shared directly or through a team are in Shared with me" do
    home = NotesHome.new(users(:carol))

    assert_empty home.my_notes
    assert_equal [ folders(:design) ], home.team_folders
    assert_equal [ folders(:alice_folder), notes(:alice_private) ], home.shared_with_me
  end

  test "everyone_access puts an item in Shared with me" do
    notes(:alice_private).update!(everyone_access: :view)

    assert_equal [ notes(:alice_private) ], NotesHome.new(users(:dave)).shared_with_me
  end

  test "a user with no access sees nothing" do
    home = NotesHome.new(users(:dave))

    assert_empty home.my_notes
    assert_empty home.team_folders
    assert_empty home.shared_with_me
  end

  test "an item inside an accessible folder isn't listed at the top level" do
    Share.create!(note: notes(:alice_nested), user: users(:carol), access: :edit)

    home = NotesHome.new(users(:carol))

    assert_not_includes all_items(home), notes(:alice_nested)
    assert_not_includes all_items(home), folders(:alice_subfolder)
  end

  test "an item shared on its own, inside a folder the user can't open, is in Shared with me" do
    Share.create!(note: notes(:alice_nested), user: users(:dave), access: :view)
    Share.create!(folder: folders(:alice_subfolder), user: users(:dave), access: :view)

    assert_equal [ folders(:alice_subfolder), notes(:alice_nested) ], NotesHome.new(users(:dave)).shared_with_me
  end

  test "a note inside a shared folder deeper down is listed inside that folder, not here" do
    deep = Note.create!(title: "Deep", author: users(:alice), folder: folders(:alice_subfolder))
    Share.create!(folder: folders(:alice_subfolder), user: users(:dave), access: :view)

    assert_equal [ folders(:alice_subfolder) ], NotesHome.new(users(:dave)).shared_with_me
    assert_not_includes all_items(NotesHome.new(users(:dave))), deep
  end

  test "My notes catches the user's note inside the team folder of a team they left" do
    note = Note.create!(title: "Bob's notes", author: users(:bob), folder: folders(:engineering))
    memberships(:bob_engineering).destroy!

    home = NotesHome.new(users(:bob))

    assert_equal [ note ], home.my_notes
    assert_empty home.team_folders
  end

  test "a team's creator stops seeing its team folder after leaving, but keeps their notes in it" do
    memberships(:alice_engineering).destroy!

    home = NotesHome.new(users(:alice))

    assert_empty home.team_folders
    assert_equal [ folders(:alice_folder), folders(:empty_folder), notes(:alice_private), notes(:eng_plan) ], home.my_notes
  end

  test "an inaccessible item never appears" do
    secret = Note.create!(title: "Secret", author: users(:alice))
    secret_folder = Folder.create!(name: "Secret", author: users(:alice))

    users(:alice, :bob, :carol, :dave).without(users(:alice)).each do |user|
      assert_not_includes all_items(NotesHome.new(user)), secret
      assert_not_includes all_items(NotesHome.new(user)), secret_folder
    end
    assert_not_includes all_items(NotesHome.new(users(:carol))), notes(:eng_plan)
    assert_not_includes all_items(NotesHome.new(users(:carol))), folders(:empty_folder)
  end

  test "every accessible item appears exactly once: at the top level or inside an open folder" do
    specs = Folder.create!(name: "Specs", author: users(:bob), parent: folders(:engineering))
    Note.create!(title: "Spec", author: users(:bob), folder: specs, everyone_access: :view)
    Note.create!(title: "Deep", author: users(:alice), folder: folders(:alice_subfolder))
    Share.create!(folder: folders(:alice_subfolder), user: users(:bob), access: :edit)
    Share.create!(note: notes(:alice_nested), team: teams(:engineering), access: :view)

    User.all.each do |user|
      listed = all_items(NotesHome.new(user))
      resolver = AccessResolver.new(user)

      assert_equal listed.uniq, listed, "#{user.name} sees an item twice"
      (Folder.all + Note.all).each do |item|
        parent = item.is_a?(Note) ? item.folder : item.parent
        expected = resolver.can_view?(item) && !(parent && resolver.can_view?(parent))
        assert_equal expected, listed.include?(item), "#{user.name}, #{item.class.name} #{item.id}"
      end
    end
  end

  test "folders come before notes, each alphabetical, ignoring case" do
    author = users(:dave)
    beta = Folder.create!(name: "beta", author: author)
    alpha = Folder.create!(name: "Alpha", author: author)
    zebra = Note.create!(title: "Zebra", author: author)
    aardvark = Note.create!(title: "aardvark", author: author)

    assert_equal [ alpha, beta, aardvark, zebra ], NotesHome.new(author).my_notes
  end

  private
    def all_items(home)
      home.my_notes + home.team_folders + home.shared_with_me
    end
end
