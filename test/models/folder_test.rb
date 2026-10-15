require "test_helper"

class FolderTest < ActiveSupport::TestCase
  test "requires a name" do
    folder = Folder.new(name: " ", author: users(:alice))

    assert_not folder.valid?
    assert_includes folder.errors[:name], "can't be blank"
  end

  test "lists its ancestors, nearest first" do
    assert_equal [ folders(:alice_folder) ], folders(:alice_subfolder).ancestors
    assert_equal [], folders(:alice_folder).ancestors
  end

  test "can be moved into another folder or to the top level" do
    folder = folders(:alice_subfolder)

    assert folder.update(parent: folders(:empty_folder))
    assert folder.update(parent: nil)
  end

  test "can't be moved inside itself" do
    folder = folders(:alice_folder)

    assert_not folder.update(parent: folder)
    assert_includes folder.errors[:parent], "can't be the folder itself or one of its subfolders"
  end

  test "can't be moved inside one of its subfolders, at any depth" do
    folder = folders(:alice_folder)
    grandchild = Folder.create!(name: "Grandchild", author: users(:alice), parent: folders(:alice_subfolder))

    [ folders(:alice_subfolder), grandchild ].each do |destination|
      assert_not folder.update(parent: destination)
      assert_includes folder.errors[:parent], "can't be the folder itself or one of its subfolders"
    end
    assert_nil folder.reload.parent
  end

  test "can be deleted when empty, which removes its shares" do
    folder = folders(:empty_folder)
    folder.shares.create!(user: users(:bob), access: :view)

    assert_difference [ "Folder.count", "Share.count" ], -1 do
      assert folder.destroy
    end
  end

  test "can't be deleted while it has a subfolder" do
    folder = folders(:alice_subfolder)
    Folder.create!(name: "Child", author: users(:alice), parent: folder)

    assert_not folder.destroy
    assert_includes folder.errors[:base], "Move or delete everything inside this folder first."
    assert Folder.exists?(folder.id)
  end

  test "can't be deleted while it has a note, and keeps its shares" do
    folder = folders(:alice_folder)

    assert_no_difference [ "Folder.count", "Share.count" ] do
      assert_not folder.destroy
    end
    assert_includes folder.errors[:base], "Move or delete everything inside this folder first."
  end

  test "a team folder can't be deleted, even when empty" do
    folder = folders(:design)

    assert_not folder.destroy
    assert_includes folder.errors[:base], "A team folder can't be deleted."
    assert Folder.exists?(folder.id)
  end

  test "a team folder can't be moved" do
    folder = folders(:engineering)

    assert_not folder.update(parent: folders(:alice_folder))
    assert_includes folder.errors[:base], "A team folder can't be moved."
  end

  test "a team folder can't be renamed on its own" do
    folder = folders(:engineering)

    assert_not folder.update(name: "Other")
    assert_includes folder.errors[:name], "of a team folder changes only with the team"
    assert_equal "Engineering", folder.reload.name
  end

  test "a team folder stays a team folder, and an ordinary folder can't become one" do
    assert_raises(ActiveRecord::ReadonlyAttributeError) { folders(:engineering).update(team_id: nil) }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { folders(:empty_folder).update(team: teams(:engineering)) }
    assert_equal teams(:engineering), folders(:engineering).reload.team
  end

  test "the database keeps a team folder at the top level even when validation is skipped" do
    folder = folders(:engineering)
    folder.parent = folders(:alice_folder)

    assert_raises(ActiveRecord::CheckViolation) { folder.save!(validate: false) }
  end

  test "a team folder's everyone access can't be changed" do
    folder = folders(:engineering)

    assert_not folder.update(everyone_access: :view)
    assert_includes folder.errors[:everyone_access], "can't be changed on a team folder"
  end

  test "a team folder can't be shared" do
    share = Share.new(folder: folders(:engineering), user: users(:carol), access: :view)

    assert_not share.valid?
    assert_includes share.errors[:folder], "is a team folder, which can't be shared"
  end

  test "the unique index allows only one folder per team" do
    folder = Folder.new(name: "Engineering", author: users(:alice), team: teams(:engineering))

    assert_raises(ActiveRecord::RecordNotUnique) { folder.save! }
  end

  test "everyone access defaults to none and only accepts none, view or edit" do
    folder = Folder.new(name: "New", author: users(:alice))
    assert folder.everyone_none?

    folder.everyone_access = "admin"
    assert_not folder.valid?
    assert_includes folder.errors[:everyone_access], "is not included in the list"
  end

  test "the database rejects an unknown everyone access" do
    assert_raises(ActiveRecord::CheckViolation) do
      Folder.insert_all!([ { name: "Bad", author_id: users(:alice).id, everyone_access: "admin" } ])
    end
  end
end
