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

  test "a hidden note and a missing one get the same 404 page" do
    switch_to users(:dave)
    get note_path(notes(:alice_private))
    hidden = [ response.status, response.media_type, response.body ]

    get note_path(id: 0)
    assert_equal hidden, [ response.status, response.media_type, response.body ]
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

  # new and create

  test "new and create make a top-level note, authored by the current user" do
    switch_to users(:dave)
    get new_note_path
    assert_response :success
    assert_select "input[name='note[folder_id]']:not([value])"
    assert_select "textarea[name='note[body]']"
    assert_select "input[name='note[lock_version]']", 0

    assert_difference "Note.count", 1 do
      post notes_path, params: { note: { title: " Dave note ", body: "# Hi", folder_id: "" } }
    end

    note = Note.last
    assert_redirected_to note
    assert_equal "Note created.", flash[:notice]
    assert_equal [ "Dave note", "# Hi", users(:dave), nil ], [ note.title, note.body, note.author, note.folder ]
  end

  test "an editor creates a note inside someone else's folder and is its author" do
    switch_to users(:bob)
    get new_note_path(folder_id: folders(:engineering))
    assert_response :success
    assert_select "h1", "New note in Engineering"
    assert_select "input[name='note[folder_id]'][value=?]", folders(:engineering).id.to_s

    assert_difference "Note.count", 1 do
      post notes_path, params: { note: { title: "Bob eng note", body: "", folder_id: folders(:engineering).id } }
    end

    note = Note.last
    assert_redirected_to note
    assert_equal [ users(:bob), folders(:engineering) ], [ note.author, note.folder ]
  end

  test "a viewer can't create a note inside the folder" do
    switch_to users(:carol)
    get new_note_path(folder_id: folders(:alice_folder))
    assert_not_allowed folders(:alice_folder)

    assert_no_difference "Note.count" do
      post notes_path, params: { note: { title: "Carol's", folder_id: folders(:alice_folder).id } }
    end
    assert_not_allowed folders(:alice_folder)
  end

  test "creating a note inside a folder without access is a 404" do
    switch_to users(:dave)
    get new_note_path(folder_id: folders(:alice_folder))
    assert_not_found

    assert_no_difference "Note.count" do
      post notes_path, params: { note: { title: "Dave's", folder_id: folders(:alice_folder).id } }
    end
    assert_not_found
  end

  test "a folder_id that isn't a single id is a 404, the same for a hidden folder and a missing one" do
    switch_to users(:dave)

    get new_note_path(folder_id: [ folders(:alice_folder).id ])
    assert_not_found
    hidden_body = response.body
    get new_note_path(folder_id: [ 0 ])
    assert_not_found
    assert_equal hidden_body, response.body

    assert_no_difference "Note.count" do
      post notes_path, params: { note: { title: "Dave's", folder_id: [ folders(:alice_folder).id ] } }
      assert_not_found
      post notes_path, params: { note: { title: "Dave's", folder_id: [ 0 ] } }
      assert_not_found
      post notes_path, params: { note: { title: "Dave's", folder_id: { id: folders(:alice_folder).id } } }
      assert_not_found
    end
  end

  test "create without a note hash is a bad request" do
    switch_to users(:dave)

    assert_no_difference "Note.count" do
      post notes_path, params: { note: "x" }
    end
    assert_response :bad_request
  end

  test "create with a blank title shows the error and keeps what was typed" do
    switch_to users(:alice)

    assert_no_difference "Note.count" do
      post notes_path, params: { note: { title: " ", body: "Draft", folder_id: folders(:alice_folder).id } }
    end

    assert_response :unprocessable_entity
    assert_select "input.is-invalid ~ .invalid-feedback", "Title can't be blank"
    assert_select "textarea[name='note[body]']", "Draft"
    assert_select "input[name='note[folder_id]'][value=?]", folders(:alice_folder).id.to_s
  end

  test "new and create ask to pick a user when there's no current user" do
    get new_note_path
    assert_asked_to_pick_user

    assert_no_difference "Note.count" do
      post notes_path, params: { note: { title: "Nobody's", folder_id: "" } }
    end
    assert_asked_to_pick_user
  end

  # edit and update

  test "the author edits a note" do
    note = notes(:alice_private)
    switch_to users(:alice)
    get edit_note_path(note)
    assert_response :success
    assert_select "input[name='note[title]'][value=?]", "Alice private"
    assert_select "textarea[name='note[body]']", "# Heading"
    assert_select "input[type=hidden][name='note[lock_version]'][value=?]", note.lock_version.to_s
    assert_select "input[name='note[folder_id]']", 0

    patch note_path(note), params: { note: { title: "Renamed", body: "New body", lock_version: note.lock_version } }

    assert_redirected_to note
    assert_equal "Note saved.", flash[:notice]
    assert_equal [ "Renamed", "New body" ], [ note.reload.title, note.body ]
  end

  test "an editor who isn't the author edits a note, but can't move it with the same form" do
    note = notes(:eng_plan)
    switch_to users(:bob)
    get edit_note_path(note)
    assert_response :success

    patch note_path(note), params: { note: { title: "Eng plan", body: "Bob's plan", folder_id: "", lock_version: note.lock_version } }

    assert_redirected_to note
    assert_equal [ "Bob's plan", folders(:engineering), users(:alice) ], [ note.reload.body, note.folder, note.author ]
  end

  test "saving over someone else's newer edit shows a message, keeps what was typed and saves nothing" do
    note = notes(:eng_plan)
    opened_version = note.lock_version
    note.update!(body: "Alice's change")
    switch_to users(:bob)

    patch note_path(note), params: { note: { title: "Bob's title", body: "Bob's change", lock_version: opened_version } }

    assert_response :conflict
    assert_select ".alert", "This note was changed by someone else."
    assert_select "input[name='note[title]'][value=?]", "Bob's title"
    assert_select "textarea[name='note[body]']", "Bob's change"
    assert_select "input[name='note[lock_version]'][value=?]", opened_version.to_s
    assert_equal [ "Eng plan", "Alice's change" ], [ note.reload.title, note.body ]
  end

  test "update without a lock_version is a bad request and changes nothing" do
    note = notes(:alice_private)
    switch_to users(:alice)

    [ {}, { lock_version: "" }, { lock_version: [ note.lock_version ] } ].each do |lock|
      patch note_path(note), params: { note: { title: "Overwritten", body: "Overwritten", **lock } }
      assert_response :bad_request
    end
    assert_equal [ "Alice private", "# Heading" ], [ note.reload.title, note.body ]
  end

  test "update changes only what the form sends" do
    note = notes(:alice_private)
    switch_to users(:alice)
    patch note_path(note), params: { note: { body: "Body only", author_id: users(:dave).id, everyone_access: "edit", lock_version: note.lock_version } }

    assert_redirected_to note
    assert_equal [ "Alice private", "Body only", users(:alice), "none" ], [ note.reload.title, note.body, note.author, note.everyone_access ]
  end

  test "create ignores an author or Everyone setting in the params, and works without a body" do
    switch_to users(:dave)
    post notes_path, params: { note: { title: "Dave note", author_id: users(:alice).id, everyone_access: "edit", folder_id: "" } }

    note = Note.last
    assert_redirected_to note
    assert_equal [ users(:dave), "none", "" ], [ note.author, note.everyone_access, note.body ]
  end

  test "update with a blank title shows the error and changes nothing" do
    note = notes(:alice_private)
    switch_to users(:alice)
    patch note_path(note), params: { note: { title: "", body: "Changed", lock_version: note.lock_version } }

    assert_response :unprocessable_entity
    assert_select "h1", "Edit \"Alice private\""
    assert_select ".invalid-feedback", "Title can't be blank"
    assert_equal [ "Alice private", "# Heading" ], [ note.reload.title, note.body ]
  end

  test "a viewer can't edit" do
    note = notes(:alice_private)
    switch_to users(:carol)
    get edit_note_path(note)
    assert_not_allowed note

    patch note_path(note), params: { note: { title: "Carol's now", lock_version: note.lock_version } }
    assert_not_allowed note
    assert_equal "Alice private", note.reload.title
  end

  test "editing without access is a 404" do
    note = notes(:alice_private)
    switch_to users(:dave)
    get edit_note_path(note)
    assert_not_found

    patch note_path(note), params: { note: { title: "Dave's now", lock_version: note.lock_version } }
    assert_not_found
    assert_equal "Alice private", note.reload.title
  end

  test "losing access while the edit page is open refuses the save" do
    note = notes(:eng_plan)
    switch_to users(:bob)
    get edit_note_path(note)
    assert_response :success
    memberships(:bob_engineering).destroy

    patch note_path(note), params: { note: { title: "Eng plan", body: "Bob's change", lock_version: note.lock_version } }
    assert_not_found
    assert_equal "The plan.", note.reload.body
  end

  test "edit and update ask to pick a user when there's no current user" do
    note = notes(:alice_private)
    get edit_note_path(note)
    assert_asked_to_pick_user

    patch note_path(note), params: { note: { title: "Nobody's", lock_version: note.lock_version } }
    assert_asked_to_pick_user
    assert_equal "Alice private", note.reload.title
  end

  # destroy

  test "the author deletes a note and goes back to its folder, or to Notes" do
    switch_to users(:alice)

    assert_difference "Note.count", -1 do
      delete note_path(notes(:alice_nested))
    end
    assert_redirected_to folders(:alice_folder)
    assert_response :see_other
    assert_equal "Note deleted.", flash[:notice]

    assert_difference [ "Note.count", "Share.count" ], -1 do
      delete note_path(notes(:alice_private))
    end
    assert_redirected_to root_path
  end

  test "an author who can't see the folder anymore goes back to Notes" do
    note = Note.create!(title: "Bob eng note", author: users(:bob), folder: folders(:engineering))
    memberships(:bob_engineering).destroy
    switch_to users(:bob)

    assert_difference "Note.count", -1 do
      delete note_path(note)
    end
    assert_redirected_to root_path
  end

  test "an editor who isn't the author can't delete" do
    switch_to users(:bob)

    assert_no_difference "Note.count" do
      delete note_path(notes(:eng_plan))
    end
    assert_not_allowed notes(:eng_plan)
  end

  test "a viewer can't delete" do
    switch_to users(:carol)

    assert_no_difference "Note.count" do
      delete note_path(notes(:alice_private))
    end
    assert_not_allowed notes(:alice_private)
  end

  test "deleting without access is a 404" do
    switch_to users(:dave)

    assert_no_difference "Note.count" do
      delete note_path(notes(:alice_private))
    end
    assert_not_found
  end

  test "destroy asks to pick a user when there's no current user" do
    assert_no_difference "Note.count" do
      delete note_path(notes(:alice_private))
    end
    assert_asked_to_pick_user
  end
end
