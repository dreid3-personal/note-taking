require "test_helper"

class ShareTest < ActiveSupport::TestCase
  test "shares a note or a folder with a user or a team" do
    assert Share.new(note: notes(:alice_private), user: users(:dave), access: :edit).valid?
    assert Share.new(note: notes(:alice_private), team: teams(:design), access: :view).valid?
    assert Share.new(folder: folders(:alice_folder), user: users(:dave), access: :view).valid?
    assert Share.new(folder: folders(:alice_folder), team: teams(:engineering), access: :edit).valid?
  end

  test "exposes the shared item and the grantee" do
    share = shares(:alice_folder_design)

    assert_equal folders(:alice_folder), share.item
    assert_equal teams(:design), share.grantee
  end

  # Exactly one of note or folder

  test "validation rejects a share with both or neither of note and folder" do
    [
      Share.new(note: notes(:alice_private), folder: folders(:alice_folder), user: users(:dave), access: :view),
      Share.new(user: users(:dave), access: :view)
    ].each do |share|
      assert_not share.valid?
      assert_includes share.errors[:base], "Share exactly one note or folder"
    end
  end

  test "the database rejects a share with both or neither of note and folder" do
    [ { note_id: notes(:alice_private).id, folder_id: folders(:alice_folder).id }, {} ].each do |item|
      assert_raises(ActiveRecord::CheckViolation) do
        Share.insert_all!([ { user_id: users(:dave).id, access: "view", **item } ])
      end
    end
  end

  # Exactly one of user or team

  test "validation rejects a share with both or neither of user and team" do
    [
      Share.new(note: notes(:alice_private), user: users(:dave), team: teams(:design), access: :view),
      Share.new(note: notes(:alice_private), access: :view)
    ].each do |share|
      assert_not share.valid?
      assert_includes share.errors[:base], "Share with exactly one user or team"
    end
  end

  test "the database rejects a share with both or neither of user and team" do
    [ { user_id: users(:dave).id, team_id: teams(:design).id }, {} ].each do |grantee|
      assert_raises(ActiveRecord::CheckViolation) do
        Share.insert_all!([ { note_id: notes(:alice_private).id, access: "view", **grantee } ])
      end
    end
  end

  # No duplicates for the same item and grantee

  DUPLICATES = [
    { note: :alice_private, user: :carol },
    { note: :alice_private, team: :design },
    { folder: :alice_folder, user: :dave },
    { folder: :alice_folder, team: :design }
  ]

  def build_duplicates
    Share.create!(note: notes(:alice_private), team: teams(:design), access: :view)
    Share.create!(folder: folders(:alice_folder), user: users(:dave), access: :view)

    DUPLICATES.map do |names|
      Share.new(
        access: :edit,
        note: names[:note] && notes(names[:note]),
        folder: names[:folder] && folders(names[:folder]),
        user: names[:user] && users(names[:user]),
        team: names[:team] && teams(names[:team])
      )
    end
  end

  test "validation rejects a duplicate share, for every item and grantee kind" do
    build_duplicates.each do |share|
      assert_not share.valid?
      assert_includes share.errors[share.user ? :user_id : :team_id], "already has a share for this item"
    end
  end

  test "the unique indexes reject a duplicate share, for every item and grantee kind, even when validation is skipped" do
    build_duplicates.each do |share|
      assert_raises(ActiveRecord::RecordNotUnique) { share.save!(validate: false) }
    end
  end

  test "the same grantee can be given shares on different items" do
    assert Share.new(note: notes(:alice_nested), user: users(:carol), access: :view).valid?
    assert Share.new(folder: folders(:alice_subfolder), team: teams(:design), access: :view).valid?
  end

  # Access level

  test "access is required and only accepts view or edit" do
    share = Share.new(note: notes(:alice_private), user: users(:dave))
    assert_not share.valid?
    assert_includes share.errors[:access], "is not included in the list"

    share.access = "none"
    assert_not share.valid?
    assert_includes share.errors[:access], "is not included in the list"
  end

  test "the database rejects an unknown access" do
    assert_raises(ActiveRecord::CheckViolation) do
      Share.insert_all!([ { note_id: notes(:alice_private).id, user_id: users(:dave).id, access: "none" } ])
    end
  end
end
