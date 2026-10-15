require "test_helper"

# The sharing page for notes and folders (the Shareable concern): GET and PATCH
# /notes/:id/sharing and /folders/:id/sharing.
#
# Fixtures: Alice's private note is shared with Carol for viewing, and "Alice folder" (holding
# "Alice nested") with Design for viewing. Alice and Bob are in Engineering, Carol is in Design,
# and Dave is in no team.
class SharingTest < ActionDispatch::IntegrationTest
  # The sharing page path for each kind of item.
  def sharing_path(item)
    item.is_a?(Folder) ? sharing_folder_path(item) : sharing_note_path(item)
  end

  # show

  test "the author sees the page: Everyone, the shares, the add forms" do
    switch_to users(:alice)
    get sharing_note_path(notes(:alice_private))

    assert_response :success
    assert_select "title", 'Share "Alice private"'
    assert_select "h1", 'Share "Alice private"'
    assert_select "form#everyone[action=?] select[name=everyone_access] option[selected]",
      sharing_note_path(notes(:alice_private)), "No access"
    assert_texts "form#everyone option", [ "No access", "Can view", "Can edit" ]
    assert_texts "#shares .col-sm-5", [ "Carol (carol@example.com)" ]
    assert_select "#shares form[action=?] select[name=?] option[selected]",
      share_path(shares(:alice_private_carol)), "share[access]", "Can view"
    assert_select "#shares form[action=?] button", share_path(shares(:alice_private_carol)), "Remove"
    assert_select "form#add_person input[type=hidden][name=?][value=?]", "share[note_id]", notes(:alice_private).id.to_s
    assert_select "form#add_person input[name=?]", "share[email]"
    assert_texts "form#add_person option", [ "Can view", "Can edit" ]
    assert_texts "form#add_team select[name='share[team_id]'] option", [ "Pick a team", "Design", "Engineering" ]
    assert_select "#inherited", count: 0
  end

  test "a folder's page posts the folder id" do
    switch_to users(:alice)
    get sharing_folder_path(folders(:alice_folder))

    assert_response :success
    assert_select "h1", 'Share "Alice folder"'
    assert_texts "#shares .col-sm-5", [ "👥 Design" ]
    assert_select "form#add_team input[type=hidden][name=?][value=?]", "share[folder_id]", folders(:alice_folder).id.to_s
  end

  test "the page lists access inherited from parent folders, nearest first" do
    folders(:alice_folder).update!(everyone_access: "view")
    Share.create!(folder: folders(:alice_subfolder), user: users(:bob), access: "edit")
    note = Note.create!(title: "Deep", author: users(:alice), folder: folders(:alice_subfolder))
    switch_to users(:alice)
    get sharing_note_path(note)

    assert_select "h2", "Also has access through a parent folder"
    assert_texts "#inherited li", [
      "Bob (can edit, from 📁 Alice subfolder)",
      "Everyone (can view, from 📁 Alice folder)",
      "👥 Design (can view, from 📁 Alice folder)"
    ]
  end

  test "the inherited list shows a parent team folder's team, and Design's view for E2E 1.4" do
    switch_to users(:alice)
    get sharing_note_path(notes(:eng_plan))
    assert_texts "#inherited li", [ "👥 Engineering (can edit, from 📁 Engineering)" ]

    get sharing_note_path(notes(:alice_nested))
    assert_texts "#inherited li", [ "👥 Design (can view, from 📁 Alice folder)" ]
  end

  # update_sharing

  test "the author sets Everyone, and back to No access" do
    note = notes(:alice_private)
    switch_to users(:alice)

    patch sharing_note_path(note), params: { everyone_access: "edit" }
    assert_redirected_to sharing_note_path(note)
    assert_equal "Everyone: Can edit.", flash[:notice]
    assert_equal "edit", note.reload.everyone_access

    patch sharing_note_path(note), params: { everyone_access: "none" }
    assert_equal "none", note.reload.everyone_access
  end

  test "Everyone works for folders too" do
    switch_to users(:alice)
    patch sharing_folder_path(folders(:alice_folder)), params: { everyone_access: "view" }

    assert_redirected_to sharing_folder_path(folders(:alice_folder))
    assert_equal "view", folders(:alice_folder).reload.everyone_access
  end

  test "an unknown Everyone level is refused, and an array is a bad request" do
    note = notes(:alice_private)
    switch_to users(:alice)

    patch sharing_note_path(note), params: { everyone_access: "admin" }
    assert_redirected_to sharing_note_path(note)
    assert_match "Everyone access", flash[:alert]

    patch sharing_note_path(note), params: { everyone_access: [ "edit" ] }
    assert_response :bad_request
    assert_equal "none", note.reload.everyone_access
  end

  # Who may use the page

  [ :get, :patch ].each do |verb|
    test "#{verb.upcase} sharing is a 404 without access, and for an item that doesn't exist" do
      switch_to users(:dave)
      [ notes(:alice_private), folders(:alice_folder) ].each do |item|
        send verb, sharing_path(item), params: { everyone_access: "edit" }
        assert_not_found
        assert_equal "none", item.reload.everyone_access
      end

      send verb, sharing_note_path(id: 0), params: { everyone_access: "edit" }
      assert_not_found
    end

    test "#{verb.upcase} sharing redirects a viewer who isn't the author, and changes nothing" do
      switch_to users(:carol)
      [ notes(:alice_private), folders(:alice_folder) ].each do |item|
        send verb, sharing_path(item), params: { everyone_access: "edit" }
        assert_not_allowed item
        assert_equal "none", item.reload.everyone_access
      end
    end

    test "#{verb.upcase} sharing redirects an editor who isn't the author, and changes nothing" do
      switch_to users(:bob)
      note = notes(:eng_plan)
      folder = Folder.create!(name: "Specs", author: users(:alice), parent: folders(:engineering))
      [ note, folder ].each do |item|
        send verb, sharing_path(item), params: { everyone_access: "edit" }
        assert_not_allowed item
        assert_equal "none", item.reload.everyone_access
      end
    end

    test "#{verb.upcase} sharing is refused for a team folder, even for its creator" do
      switch_to users(:alice)
      send verb, sharing_folder_path(folders(:engineering)), params: { everyone_access: "edit" }
      assert_not_allowed folders(:engineering)

      switch_to users(:carol)
      send verb, sharing_folder_path(folders(:engineering)), params: { everyone_access: "edit" }
      assert_not_found
      assert_equal "none", folders(:engineering).reload.everyone_access
    end

    test "#{verb.upcase} sharing asks to pick a user when there's no current user" do
      send verb, sharing_note_path(notes(:alice_private)), params: { everyone_access: "edit" }
      assert_asked_to_pick_user
      assert_equal "none", notes(:alice_private).reload.everyone_access
    end
  end

  test "the note and folder pages link to the sharing page for the author only" do
    switch_to users(:alice)
    get note_path(notes(:alice_private))
    assert_select "a[href=?]", sharing_note_path(notes(:alice_private)), "Share"

    switch_to users(:carol)
    get note_path(notes(:alice_private))
    assert_no_buttons "Share"
  end
end
