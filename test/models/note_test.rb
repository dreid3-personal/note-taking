require "test_helper"

class NoteTest < ActiveSupport::TestCase
  test "requires a title" do
    note = Note.new(title: "  ", author: users(:alice))

    assert_not note.valid?
    assert_includes note.errors[:title], "can't be blank"
  end

  test "can sit at the top level or inside a folder" do
    assert Note.new(title: "Top", author: users(:alice)).valid?
    assert Note.new(title: "Inside", author: users(:alice), folder: folders(:alice_folder)).valid?
  end

  test "saving with an old lock_version fails and keeps the newer content" do
    first_copy = Note.find(notes(:eng_plan).id)
    second_copy = Note.find(notes(:eng_plan).id)

    first_copy.update!(body: "First edit")

    assert_raises(ActiveRecord::StaleObjectError) { second_copy.update!(body: "Second edit") }
    assert_equal "First edit", notes(:eng_plan).reload.body
  end

  test "deleting a note removes its shares" do
    assert_difference [ "Note.count", "Share.count" ], -1 do
      notes(:alice_private).destroy
    end
  end

  test "everyone access defaults to none and only accepts none, view or edit" do
    note = Note.new(title: "New", author: users(:alice))
    assert note.everyone_none?

    note.everyone_access = "admin"
    assert_not note.valid?
    assert_includes note.errors[:everyone_access], "is not included in the list"
  end

  test "the database rejects an unknown everyone access" do
    assert_raises(ActiveRecord::CheckViolation) do
      Note.insert_all!([ { title: "Bad", author_id: users(:alice).id, everyone_access: "admin" } ])
    end
  end
end
