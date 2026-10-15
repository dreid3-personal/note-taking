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

  test "a title can be up to 200 characters" do
    assert Note.new(title: "a" * 200, author: users(:alice)).valid?

    note = Note.new(title: "a" * 201, author: users(:alice))
    assert_not note.valid?
    assert_includes note.errors[:title], "is too long (maximum is 200 characters)"
  end

  test "a body can be up to 100,000 characters, and the error says how long it is" do
    assert Note.new(title: "Long", body: "a" * 100_000, author: users(:alice)).valid?

    note = Note.new(title: "Long", body: "a" * 100_001, author: users(:alice))
    assert_not note.valid?
    assert_includes note.errors[:body], "is too long (100,001 characters; the maximum is 100,000)"
  end

  # Browsers count a line break as one character for maxlength but submit it as \r\n.
  test "saves line breaks in the body as \\n, so the form's limit and the model's agree" do
    assert_equal "one\ntwo\n", Note.new(body: "one\r\ntwo\r\n").body
  end
end
