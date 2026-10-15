require "test_helper"

# POST /shares, PATCH /shares/:id and DELETE /shares/:id, from the sharing page.
#
# Fixtures: Alice's private note is shared with Carol for viewing, and "Alice folder" (holding
# "Alice nested") with Design for viewing. Alice and Bob are in Engineering, Carol is in Design,
# and Dave is in no team.
class SharesControllerTest < ActionDispatch::IntegrationTest
  def add_person(item, email, access = "view")
    post shares_path, params: { share: { item_key(item) => item.id, email: email, access: access } }
  end

  def add_team(item, team, access = "view")
    post shares_path, params: { share: { item_key(item) => item.id, team_id: team.id, access: access } }
  end

  def item_key(item)
    item.is_a?(Folder) ? :folder_id : :note_id
  end

  def sharing_path(item)
    item.is_a?(Folder) ? sharing_folder_path(item) : sharing_note_path(item)
  end

  # A note in the Engineering team folder that Alice wrote: Bob can edit it, but isn't its author.
  def eng_plan
    notes(:eng_plan)
  end

  # create

  test "the author adds a person by email" do
    note = notes(:alice_private)
    switch_to users(:alice)

    assert_difference -> { note.shares.count } do
      add_person note, "dave@example.com", "edit"
    end
    assert_redirected_to sharing_note_path(note)
    assert_response :see_other
    assert_equal "Dave added: Can edit.", flash[:notice]
    assert_equal "edit", note.shares.find_by!(user: users(:dave)).access
  end

  test "the email is looked up like User's: trimmed and lowercased" do
    note = notes(:alice_nested)
    switch_to users(:alice)
    add_person note, "  CAROL@Example.com "

    assert_equal "Carol added: Can view.", flash[:notice]
    assert note.shares.exists?(user: users(:carol), access: "view")
  end

  test "an unknown email adds nothing" do
    switch_to users(:alice)
    assert_no_difference -> { Share.count } do
      add_person notes(:alice_private), "nobody@example.com"
    end
    assert_redirected_to sharing_note_path(notes(:alice_private))
    assert_equal "No user with that email.", flash[:alert]

    follow_redirect!
    assert_select ".alert-danger", "No user with that email."
  end

  test "the author adds a team to a folder" do
    folder = folders(:empty_folder)
    switch_to users(:alice)

    assert_difference -> { folder.shares.count } do
      add_team folder, teams(:engineering), "edit"
    end
    assert_redirected_to sharing_folder_path(folder)
    assert_equal "Engineering added: Can edit.", flash[:notice]
    assert folder.shares.exists?(team: teams(:engineering), access: "edit")
  end

  test "no team picked adds nothing" do
    switch_to users(:alice)
    assert_no_difference -> { Share.count } do
      post shares_path, params: { share: { note_id: notes(:alice_private).id, team_id: "", access: "view" } }
    end
    assert_equal "Pick a team.", flash[:alert]
  end

  test "a duplicate share changes nothing and says so" do
    switch_to users(:alice)
    assert_no_difference -> { Share.count } do
      add_person notes(:alice_private), "carol@example.com", "edit"
      add_team folders(:alice_folder), teams(:design), "edit"
    end
    assert_equal "Design already has access. Change it in the list above.", flash[:alert]
    assert_equal "view", shares(:alice_private_carol).reload.access
    assert_equal "view", shares(:alice_folder_design).reload.access
  end

  test "sharing with the author themself adds nothing" do
    switch_to users(:alice)
    assert_no_difference -> { Share.count } do
      add_person notes(:alice_private), "alice@example.com"
    end
    assert_equal "You're the author, so you already have access.", flash[:alert]
  end

  test "an unknown access level adds nothing" do
    switch_to users(:alice)
    assert_no_difference -> { Share.count } do
      add_person notes(:alice_private), "dave@example.com", "owner"
    end
    assert_match "Access", flash[:alert]
  end

  test "create is a 404 for an item without access, or that doesn't exist" do
    switch_to users(:dave)
    assert_no_difference -> { Share.count } do
      add_person notes(:alice_private), "dave@example.com", "edit"
      assert_not_found
      add_team folders(:alice_folder), teams(:engineering), "edit"
      assert_not_found
      post shares_path, params: { share: { note_id: 0, email: "dave@example.com", access: "edit" } }
      assert_not_found
    end
  end

  test "create redirects a viewer or editor who isn't the author" do
    switch_to users(:carol)
    assert_no_difference -> { Share.count } do
      add_person notes(:alice_private), "carol@example.com", "edit"
      assert_not_allowed notes(:alice_private)
      add_person folders(:alice_folder), "carol@example.com", "edit"
      assert_not_allowed folders(:alice_folder)
    end

    switch_to users(:bob)
    assert_no_difference -> { Share.count } do
      add_person eng_plan, "dave@example.com", "edit"
      assert_not_allowed eng_plan
    end
  end

  test "create on another user's item is refused even when the poster authors something else" do
    # Bob owns a note, but posts Alice's note id: authorship is checked on the posted item.
    Note.create!(title: "Bob's", author: users(:bob))
    switch_to users(:bob)

    assert_no_difference -> { Share.count } do
      add_person notes(:alice_private), "bob@example.com", "edit"
      assert_not_found
      add_person eng_plan, "bob@example.com", "edit"
      assert_not_allowed eng_plan
    end
  end

  test "create is refused for a team folder, even for its creator" do
    switch_to users(:alice)
    assert_no_difference -> { Share.count } do
      add_person folders(:engineering), "dave@example.com"
    end
    assert_not_allowed folders(:engineering)

    switch_to users(:carol)
    add_person folders(:engineering), "dave@example.com"
    assert_not_found
  end

  test "create asks to pick a user when there's no current user" do
    assert_no_difference -> { Share.count } do
      add_person notes(:alice_private), "dave@example.com"
    end
    assert_asked_to_pick_user
  end

  test "a crafted item id is a 404 like a missing one, and nothing is added" do
    switch_to users(:dave)
    hidden = notes(:alice_private).id

    assert_no_difference -> { Share.count } do
      [
        { note_id: [ hidden ] },
        { note_id: [ 0 ] },
        { note_id: { id: hidden } },
        { note_id: hidden, folder_id: folders(:alice_folder).id },
        {}
      ].each do |ids|
        post shares_path, params: { share: { email: "dave@example.com", access: "edit", **ids } }
        assert_not_found
      end

      post shares_path, params: { share: "x" }
      assert_not_found
    end

    # The author gets the same 404 for an array, or for both a note and a folder id, even though
    # they wrote both: only a single id names an item.
    switch_to users(:alice)
    assert_no_difference -> { Share.count } do
      post shares_path, params: { share: { note_id: [ hidden ], email: "dave@example.com", access: "edit" } }
      assert_not_found
      post shares_path, params: { share: { note_id: hidden, folder_id: folders(:alice_folder).id, email: "dave@example.com", access: "edit" } }
      assert_not_found
    end
  end

  # update

  test "the author lowers a share from edit to view, and the grantee loses edit at once" do
    share = shares(:alice_private_carol)
    share.update!(access: "edit")
    switch_to users(:alice)

    patch share_path(share), params: { share: { access: "view" } }
    assert_redirected_to sharing_note_path(notes(:alice_private))
    assert_equal "Carol: Can view.", flash[:notice]
    assert_equal "view", share.reload.access
    assert_not AccessResolver.new(users(:carol)).can_edit?(notes(:alice_private))
  end

  test "update ignores anything but the access level" do
    share = shares(:alice_private_carol)
    switch_to users(:alice)
    patch share_path(share), params: { share: { access: "edit", user_id: users(:dave).id, note_id: notes(:alice_nested).id } }

    share.reload
    assert_equal [ "edit", users(:carol), notes(:alice_private) ], [ share.access, share.user, share.note ]
  end

  test "update with an unknown level changes nothing" do
    share = shares(:alice_private_carol)
    switch_to users(:alice)
    patch share_path(share), params: { share: { access: "owner" } }

    assert_match "Access", flash[:alert]
    assert_equal "view", share.reload.access
  end

  test "update is a 404 without access, and for a share that doesn't exist" do
    switch_to users(:dave)
    patch share_path(shares(:alice_private_carol)), params: { share: { access: "edit" } }
    assert_not_found
    patch share_path(id: 0), params: { share: { access: "edit" } }
    assert_not_found
    assert_equal "view", shares(:alice_private_carol).reload.access
  end

  test "update redirects a grantee who isn't the author, so they can't raise their own access" do
    switch_to users(:carol)
    patch share_path(shares(:alice_private_carol)), params: { share: { access: "edit" } }
    assert_not_allowed notes(:alice_private)
    patch share_path(shares(:alice_folder_design)), params: { share: { access: "edit" } }
    assert_not_allowed folders(:alice_folder)

    assert_equal "view", shares(:alice_private_carol).reload.access
    assert_equal "view", shares(:alice_folder_design).reload.access
  end

  test "update redirects an editor who isn't the author" do
    share = Share.create!(note: eng_plan, user: users(:dave), access: "view")
    switch_to users(:bob)
    patch share_path(share), params: { share: { access: "edit" } }

    assert_not_allowed eng_plan
    assert_equal "view", share.reload.access
  end

  test "update asks to pick a user when there's no current user" do
    patch share_path(shares(:alice_private_carol)), params: { share: { access: "edit" } }
    assert_asked_to_pick_user
    assert_equal "view", shares(:alice_private_carol).reload.access
  end

  # destroy

  test "the author removes a share, and the grantee loses access" do
    switch_to users(:alice)
    assert_difference -> { Share.count }, -1 do
      delete share_path(shares(:alice_private_carol))
    end
    assert_redirected_to sharing_note_path(notes(:alice_private))
    assert_equal "Carol removed.", flash[:notice]
    assert_not AccessResolver.new(users(:carol)).can_view?(notes(:alice_private))
  end

  test "destroy is a 404 without access, and for a share that doesn't exist" do
    switch_to users(:dave)
    assert_no_difference -> { Share.count } do
      delete share_path(shares(:alice_private_carol))
      assert_not_found
      delete share_path(id: 0)
      assert_not_found
    end
  end

  test "destroy redirects a viewer or editor who isn't the author" do
    share = Share.create!(note: eng_plan, user: users(:dave), access: "view")

    assert_no_difference -> { Share.count } do
      switch_to users(:carol)
      delete share_path(shares(:alice_folder_design))
      assert_not_allowed folders(:alice_folder)

      switch_to users(:bob)
      delete share_path(share)
      assert_not_allowed eng_plan
    end
  end

  test "destroy asks to pick a user when there's no current user" do
    assert_no_difference -> { Share.count } do
      delete share_path(shares(:alice_private_carol))
    end
    assert_asked_to_pick_user
  end

  test "a share on a team folder can't exist, so its endpoints have nothing to act on" do
    share = Share.new(folder: folders(:engineering), user: users(:dave), access: "view")
    assert_not share.valid?
  end
end
