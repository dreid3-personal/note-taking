require "test_helper"

# Fixtures: Alice owns "Alice folder" (shared with Design for viewing, so Carol can view it) with
# "Alice subfolder" (empty) and the note "Alice nested" inside, plus the top-level "Empty folder".
# Alice and Bob are in Engineering, Carol is in Design, and Dave is in no team.
class FoldersControllerTest < ActionDispatch::IntegrationTest
  # A folder Alice made inside the Engineering team folder: Bob can edit it, but isn't its author.
  def alice_folder_in_engineering
    Folder.create!(name: "Specs", author: users(:alice), parent: folders(:engineering))
  end

  # show

  test "show lists the folder's contents, folders first, with each item's author" do
    switch_to users(:alice)
    get folder_path(folders(:alice_folder))

    assert_response :success
    assert_select "h1", "📁 Alice folder"
    assert_select "tbody tr", 2
    assert_select "tbody tr:nth-child(1) a[href=?]", folder_path(folders(:alice_subfolder)), "Alice subfolder"
    assert_select "tbody tr:nth-child(2) a[href=?]", note_path(notes(:alice_nested)), "Alice nested"
    assert_select "tbody tr:nth-child(2) td", "Alice"
  end

  test "show gives the author every button" do
    switch_to users(:alice)
    get folder_path(folders(:alice_folder))

    assert_select "a[href=?]", edit_folder_path(folders(:alice_folder)), "Rename"
    assert_select "a[href=?]", sharing_folder_path(folders(:alice_folder)), "Share"
    assert_select "a[href=?]", move_folder_path(folders(:alice_folder)), "Move"
    assert_select "form[action=?][data-turbo-confirm] button", folder_path(folders(:alice_folder)), "Delete"
    assert_select "a[href=?]", new_folder_path(parent_id: folders(:alice_folder)), "+ New folder"
    assert_select "a[href=?]", new_note_path(folder_id: folders(:alice_folder)), "+ New note"
  end

  test "show gives a viewer no buttons" do
    switch_to users(:carol)
    get folder_path(folders(:alice_folder))

    assert_response :success
    assert_no_buttons "Rename", "Share", "Move", "Delete", "+ New folder", "+ New note"
  end

  test "show gives an editor who isn't the author Rename and New, but not Share, Move or Delete" do
    folder = alice_folder_in_engineering
    switch_to users(:bob)
    get folder_path(folder)

    assert_select "a", "Rename"
    assert_select "a", "+ New folder"
    assert_select "a", "+ New note"
    assert_no_buttons "Share", "Move", "Delete"
  end

  test "show gives a team folder no Rename, Share, Move or Delete, even for its creator" do
    switch_to users(:alice)
    get folder_path(folders(:engineering))

    assert_select "a", "+ New folder"
    assert_select "a", "+ New note"
    assert_no_buttons "Rename", "Share", "Move", "Delete"
  end

  test "show is a 404 without access, and for a folder that doesn't exist" do
    switch_to users(:dave)
    get folder_path(folders(:alice_folder))
    assert_not_found

    get folder_path(id: 0)
    assert_not_found
  end

  test "a team folder is a 404 for someone outside the team, including its creator after leaving" do
    switch_to users(:carol)
    get folder_path(folders(:engineering))
    assert_not_found

    memberships(:alice_engineering).destroy
    switch_to users(:alice)
    get folder_path(folders(:engineering))
    assert_not_found
  end

  test "show asks to pick a user when there's no current user" do
    get folder_path(folders(:alice_folder))

    assert_asked_to_pick_user
  end

  # Breadcrumbs

  test "breadcrumbs start at the section the top folder is listed in" do
    switch_to users(:alice)
    get folder_path(folders(:alice_subfolder))
    assert_texts ".breadcrumb a", [ "Notes", "My notes", "Alice folder", "Alice subfolder" ]
    assert_select ".breadcrumb a[href=?]", root_path(anchor: "my-notes")

    switch_to users(:carol)
    get folder_path(folders(:alice_subfolder))
    assert_texts ".breadcrumb a", [ "Notes", "Shared with me", "Alice folder", "Alice subfolder" ]

    switch_to users(:bob)
    get folder_path(alice_folder_in_engineering)
    assert_texts ".breadcrumb a", [ "Notes", "Team folders", "Engineering", "Specs" ]
  end

  # new and create

  test "new and create make a top-level folder, authored by the current user" do
    switch_to users(:dave)
    get new_folder_path
    assert_response :success
    assert_select "input[name='folder[parent_id]']:not([value])"

    assert_difference "Folder.count", 1 do
      post folders_path, params: { folder: { name: " Dave folder ", parent_id: "" } }
    end

    folder = Folder.last
    assert_redirected_to folder
    assert_equal [ "Dave folder", users(:dave), nil ], [ folder.name, folder.author, folder.parent ]
  end

  test "an editor creates a folder inside someone else's folder and is its author" do
    switch_to users(:bob)
    get new_folder_path(parent_id: folders(:engineering))
    assert_response :success
    assert_select "input[name='folder[parent_id]'][value=?]", folders(:engineering).id.to_s

    assert_difference "Folder.count", 1 do
      post folders_path, params: { folder: { name: "Bob specs", parent_id: folders(:engineering).id } }
    end

    folder = Folder.last
    assert_equal [ users(:bob), folders(:engineering) ], [ folder.author, folder.parent ]
  end

  test "a viewer can't create a folder inside the folder" do
    switch_to users(:carol)
    get new_folder_path(parent_id: folders(:alice_folder))
    assert_not_allowed folders(:alice_folder)

    assert_no_difference "Folder.count" do
      post folders_path, params: { folder: { name: "Carol's", parent_id: folders(:alice_folder).id } }
    end
    assert_not_allowed folders(:alice_folder)
  end

  test "creating inside a folder without access is a 404" do
    switch_to users(:dave)
    get new_folder_path(parent_id: folders(:alice_folder))
    assert_not_found

    assert_no_difference "Folder.count" do
      post folders_path, params: { folder: { name: "Dave's", parent_id: folders(:alice_folder).id } }
    end
    assert_not_found
  end

  test "a parent_id that isn't a single id is a 404, the same for a hidden folder and a missing one" do
    switch_to users(:dave)

    get new_folder_path(parent_id: [ folders(:alice_folder).id ])
    assert_not_found
    hidden_body = response.body
    get new_folder_path(parent_id: [ 0 ])
    assert_not_found
    assert_equal hidden_body, response.body

    assert_no_difference "Folder.count" do
      post folders_path, params: { folder: { name: "Dave's", parent_id: [ folders(:alice_folder).id ] } }
      assert_not_found
      post folders_path, params: { folder: { name: "Dave's", parent_id: [ 0 ] } }
      assert_not_found
    end
  end

  test "a hidden folder and a missing one get the same 404 page" do
    switch_to users(:dave)
    get folder_path(folders(:alice_folder))
    hidden = [ response.status, response.media_type, response.body ]

    get folder_path(id: 0)
    assert_equal hidden, [ response.status, response.media_type, response.body ]
  end

  test "create without a folder hash is a bad request" do
    switch_to users(:dave)

    assert_no_difference "Folder.count" do
      post folders_path, params: { folder: "x" }
    end
    assert_response :bad_request
  end

  test "create with a blank name shows the error" do
    switch_to users(:alice)

    assert_no_difference "Folder.count" do
      post folders_path, params: { folder: { name: " ", parent_id: folders(:alice_folder).id } }
    end

    assert_response :unprocessable_entity
    assert_select "input.is-invalid ~ .invalid-feedback", "Name can't be blank"
    assert_select "input[name='folder[parent_id]'][value=?]", folders(:alice_folder).id.to_s
  end

  test "new and create ask to pick a user when there's no current user" do
    get new_folder_path
    assert_asked_to_pick_user

    assert_no_difference "Folder.count" do
      post folders_path, params: { folder: { name: "Nobody's", parent_id: "" } }
    end
    assert_asked_to_pick_user
  end

  # edit and update (rename)

  test "the author renames a folder" do
    switch_to users(:alice)
    get edit_folder_path(folders(:alice_folder))
    assert_response :success

    patch folder_path(folders(:alice_folder)), params: { folder: { name: "Renamed" } }

    assert_redirected_to folders(:alice_folder)
    assert_equal "Renamed", folders(:alice_folder).reload.name
  end

  test "an editor who isn't the author can rename, but not move it with the same form" do
    folder = alice_folder_in_engineering
    switch_to users(:bob)
    get edit_folder_path(folder)
    assert_response :success

    patch folder_path(folder), params: { folder: { name: "Bob's name", parent_id: "" } }

    assert_redirected_to folder
    assert_equal [ "Bob's name", folders(:engineering) ], [ folder.reload.name, folder.parent ]
  end

  test "rename with a blank name shows the error and changes nothing" do
    switch_to users(:alice)
    patch folder_path(folders(:alice_folder)), params: { folder: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "h1", "Rename \"Alice folder\""
    assert_select ".invalid-feedback", "Name can't be blank"
    assert_equal "Alice folder", folders(:alice_folder).reload.name
  end

  test "a viewer can't rename" do
    switch_to users(:carol)
    get edit_folder_path(folders(:alice_folder))
    assert_not_allowed folders(:alice_folder)

    patch folder_path(folders(:alice_folder)), params: { folder: { name: "Carol's now" } }
    assert_not_allowed folders(:alice_folder)
    assert_equal "Alice folder", folders(:alice_folder).reload.name
  end

  test "renaming without access is a 404" do
    switch_to users(:dave)
    get edit_folder_path(folders(:alice_folder))
    assert_not_found

    patch folder_path(folders(:alice_folder)), params: { folder: { name: "Dave's now" } }
    assert_not_found
    assert_equal "Alice folder", folders(:alice_folder).reload.name
  end

  test "nobody can rename a team folder here, not even its creator" do
    [ users(:alice), users(:bob) ].each do |user|
      switch_to user
      get edit_folder_path(folders(:engineering))
      assert_not_allowed folders(:engineering)

      patch folder_path(folders(:engineering)), params: { folder: { name: "Renamed" } }
      assert_not_allowed folders(:engineering)
    end
    assert_equal "Engineering", folders(:engineering).reload.name
  end

  test "edit and update ask to pick a user when there's no current user" do
    get edit_folder_path(folders(:alice_folder))
    assert_asked_to_pick_user

    patch folder_path(folders(:alice_folder)), params: { folder: { name: "Nobody's" } }
    assert_asked_to_pick_user
    assert_equal "Alice folder", folders(:alice_folder).reload.name
  end

  # destroy

  test "the author deletes an empty folder and goes back to where it was" do
    switch_to users(:alice)

    assert_difference "Folder.count", -1 do
      delete folder_path(folders(:empty_folder))
    end
    assert_redirected_to root_path
    assert_response :see_other

    assert_difference "Folder.count", -1 do
      delete folder_path(folders(:alice_subfolder))
    end
    assert_redirected_to folders(:alice_folder)
  end

  test "a folder with something inside isn't deleted" do
    switch_to users(:alice)

    assert_no_difference "Folder.count" do
      delete folder_path(folders(:alice_folder))
    end

    assert_redirected_to folders(:alice_folder)
    assert_equal "Move or delete everything inside this folder first.", flash[:alert]
  end

  test "an editor who isn't the author can't delete" do
    folder = alice_folder_in_engineering
    switch_to users(:bob)

    assert_no_difference "Folder.count" do
      delete folder_path(folder)
    end
    assert_not_allowed folder
  end

  test "a viewer can't delete" do
    switch_to users(:carol)

    assert_no_difference "Folder.count" do
      delete folder_path(folders(:alice_subfolder))
    end
    assert_not_allowed folders(:alice_subfolder)
  end

  test "deleting without access is a 404" do
    switch_to users(:dave)

    assert_no_difference "Folder.count" do
      delete folder_path(folders(:empty_folder))
    end
    assert_not_found
  end

  test "nobody can delete a team folder, not even its creator" do
    folders(:engineering).notes.destroy_all

    [ users(:alice), users(:bob) ].each do |user|
      switch_to user
      assert_no_difference "Folder.count" do
        delete folder_path(folders(:engineering))
      end
      assert_not_allowed folders(:engineering)
    end
  end

  test "destroy asks to pick a user when there's no current user" do
    assert_no_difference "Folder.count" do
      delete folder_path(folders(:empty_folder))
    end
    assert_asked_to_pick_user
  end
end
