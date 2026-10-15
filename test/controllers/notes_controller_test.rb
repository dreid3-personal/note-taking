require "test_helper"

class NotesControllerTest < ActionDispatch::IntegrationTest
  test "with no current user, the Notes page asks to pick one" do
    get root_path

    assert_response :success
    assert_select "p", "Pick a user in the sidebar to get started."
    assert_select "a[href=?]", users_path, text: /Add one/, count: 0
    assert_select "select[name=user_id] option", "Alice"
  end

  test "with no users at all, the Notes page links to the Users page" do
    [ Share, Note, Folder, Membership, Team, User ].each(&:delete_all)
    get root_path

    assert_select "p", "Pick a user in the sidebar to get started."
    assert_select "a[href=?]", users_path, text: "Add one on the Users page"
  end

  test "with a current user, the message is gone" do
    patch current_user_path, params: { user_id: users(:alice).id }
    get root_path

    assert_select "p", text: "Pick a user in the sidebar to get started.", count: 0
  end

  test "the Notes link is highlighted on the Notes page, and the Users link on the Users page" do
    get root_path
    assert_select ".sidebar a.active", "📄 Notes"

    get users_path
    assert_select ".sidebar a.active", "👤 Users"
  end

  # The Notes home

  test "the Notes home lists each section's items, folders first, with author and buttons" do
    switch_to users(:alice)
    get root_path

    assert_select "#my-notes tbody tr", 3
    assert_select "#my-notes tbody tr:nth-child(1) a[href=?]", folder_path(folders(:alice_folder)), "Alice folder"
    assert_select "#my-notes tbody tr:nth-child(2) a[href=?]", folder_path(folders(:empty_folder)), "Empty folder"
    assert_select "#my-notes tbody tr:nth-child(3) a[href=?]", note_path(notes(:alice_private)), "Alice private"
    assert_select "#team-folders tbody tr", 1
    assert_select "#team-folders tbody tr td", "Team"
    assert_select "#team-folders a[href=?]", folder_path(folders(:engineering)), "Engineering"
    assert_select "#shared-with-me tbody tr", 0
    assert_select "#shared-with-me p", "Nothing here yet."
    assert_select "a[href=?]", new_folder_path, "+ New folder"
    assert_select "a[href=?]", new_note_path, "+ New note"
  end

  test "Shared with me lists items other people shared, but not what's inside them" do
    switch_to users(:carol)
    get root_path

    assert_select "#my-notes tbody tr", 0
    assert_texts "#team-folders a", [ "Design" ]
    assert_texts "#shared-with-me a", [ "Alice folder", "Alice private" ]
    assert_select "#shared-with-me tbody tr:nth-child(1) td", "Alice"
    assert_select "a", text: "Alice nested", count: 0
  end

  test "a user with no access sees empty sections" do
    switch_to users(:dave)
    get root_path

    assert_select "tbody tr", 0
    assert_select "p", text: "Nothing here yet.", count: 3
  end

  test "with no current user, the Notes home has no sections or New buttons" do
    get root_path

    assert_select "#my-notes", count: 0
    assert_select "a", text: "+ New note", count: 0
  end

  # show

  test "show renders the note's Markdown, author and breadcrumbs" do
    notes(:alice_private).update!(body: "# Heading
- [ ] a task
<script>alert(\"xss\")</script>
")
    switch_to users(:alice)
    get note_path(notes(:alice_private))

    assert_response :success
    assert_select "h1", "📄 Alice private"
    assert_select ".note-body h1", "Heading"
    assert_select ".note-body li input[type=checkbox]"
    assert_select "script", text: /xss/, count: 0
    assert_select "main p", /By Alice/
    assert_texts ".breadcrumb a", [ "Notes", "My notes" ]
  end

  test "show gives the author every button" do
    switch_to users(:alice)
    get note_path(notes(:alice_nested))

    assert_select "a[href=?]", edit_note_path(notes(:alice_nested)), "Edit"
    assert_select "a[href=?]", sharing_note_path(notes(:alice_nested)), "Share"
    assert_select "a[href=?]", move_note_path(notes(:alice_nested)), "Move"
    assert_select "form[action=?][data-turbo-confirm] button", note_path(notes(:alice_nested)), "Delete"
    assert_texts ".breadcrumb a", [ "Notes", "My notes", "Alice folder" ]
  end

  test "show gives a viewer no buttons" do
    switch_to users(:carol)
    get note_path(notes(:alice_nested))

    assert_response :success
    assert_no_buttons "Edit", "Share", "Move", "Delete"
    assert_texts ".breadcrumb a", [ "Notes", "Shared with me", "Alice folder" ]
  end

  test "show gives an editor who isn't the author Edit only" do
    switch_to users(:bob)
    get note_path(notes(:eng_plan))

    assert_select "a", "Edit"
    assert_no_buttons "Share", "Move", "Delete"
    assert_texts ".breadcrumb a", [ "Notes", "Team folders", "Engineering" ]
  end

  test "show is a 404 without access, and for a note that doesn't exist" do
    switch_to users(:dave)
    get note_path(notes(:alice_private))
    assert_not_found

    switch_to users(:bob)
    get note_path(notes(:alice_nested))
    assert_not_found

    get note_path(id: 0)
    assert_not_found
  end

  test "an author still sees their note in a team folder after leaving the team, under My notes" do
    note = Note.create!(title: "Bob eng note", author: users(:bob), folder: folders(:engineering))
    memberships(:bob_engineering).destroy
    switch_to users(:bob)

    get note_path(note)
    assert_response :success
    assert_texts ".breadcrumb a", [ "Notes", "My notes" ]

    get root_path
    assert_texts "#my-notes a", [ "Bob eng note" ]
    assert_select "#team-folders tbody tr", 0
  end

  test "show asks to pick a user when there's no current user" do
    get note_path(notes(:alice_private))

    assert_asked_to_pick_user
  end
end
