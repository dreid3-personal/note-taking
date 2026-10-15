require "test_helper"

# /api/notes and /api/home. In the fixtures, Alice private is shared with Carol for viewing, Alice
# folder (holding Alice nested) with the Design team (Carol) for viewing, and Eng plan sits in the
# Engineering team folder (Alice and Bob). Dave has access to none of them.
class Api::NotesTest < ActionDispatch::IntegrationTest
  setup do
    @note = notes(:alice_private)
  end

  test "every notes endpoint needs a current user" do
    api :get, "/api/home"
    assert_api_unauthorized
    api :get, "/api/notes"
    assert_api_unauthorized
    api :get, "/api/notes/#{@note.id}"
    assert_api_unauthorized
    assert_no_difference -> { Note.count } do
      api :post, "/api/notes", params: { title: "New" }
      assert_api_unauthorized
      api :delete, "/api/notes/#{@note.id}"
      assert_api_unauthorized
    end
    api :patch, "/api/notes/#{@note.id}", params: { title: "Changed", lock_version: 0 }
    assert_api_unauthorized
    assert_equal "Alice private", @note.reload.title
  end

  test "home lists the top level in three sections" do
    api :get, "/api/home", as: users(:carol)
    assert_response :ok
    assert_equal [], response.parsed_body["my_notes"]
    assert_equal [ "Design" ], response.parsed_body["team_folders"].pluck("name")
    assert_equal [ [ "folder", "Alice folder" ], [ "note", "Alice private" ] ],
      response.parsed_body["shared_with_me"].map { |item| [ item["type"], item["name"] || item["title"] ] }

    api :get, "/api/home", as: users(:dave)
    assert_equal({ "my_notes" => [], "team_folders" => [], "shared_with_me" => [] }, response.parsed_body)
  end

  test "the notes index lists only notes the user can open" do
    api :get, "/api/notes", as: users(:carol)
    assert_response :ok
    assert_equal [ "Alice nested", "Alice private" ], response.parsed_body.pluck("title")

    api :get, "/api/notes", as: users(:dave)
    assert_equal [], response.parsed_body
  end

  test "showing a note includes its Markdown, sanitized HTML and lock_version" do
    @note.update!(body: "# Hi\n\n<script>alert(1)</script>")
    api :get, "/api/notes/#{@note.id}", as: users(:carol)
    assert_response :ok
    json = response.parsed_body
    assert_equal "# Hi\n\n<script>alert(1)</script>", json["body"]
    assert_includes json["body_html"], "<h1>Hi</h1>"
    assert_not_includes json["body_html"], "<script"
    assert_equal 1, json["lock_version"]
    assert_equal "view", json["access"]
    assert_equal({ "id" => users(:alice).id, "name" => "Alice" }, json["author"])
    assert_not json.key?("everyone_access"), "only the author sees sharing settings, on /shares"
  end

  test "a hidden note is a 404 identical to a missing one" do
    api :get, "/api/notes/0", as: users(:dave)
    missing = response.body
    assert_api_not_found

    [ @note.id, "#{@note.id}abc" ].each do |id|
      api :get, "/api/notes/#{id}", as: users(:dave)
      assert_api_not_found
      assert_equal missing, response.body
    end
  end

  test "a note shown on its own doesn't reveal the hidden folder it sits in" do
    nested = notes(:alice_nested)
    Share.create!(note: nested, user: users(:dave), access: :view)

    api :get, "/api/notes/#{nested.id}", as: users(:dave)
    assert_response :ok
    assert_nil response.parsed_body["folder_id"]

    api :get, "/api/notes/#{nested.id}", as: users(:carol)
    assert_equal folders(:alice_folder).id, response.parsed_body["folder_id"]
  end

  test "creating a note at the top level or in a folder the user can edit" do
    api :post, "/api/notes", as: users(:dave), params: { title: " Dave's ", body: "Hi" }
    assert_response :created
    note = Note.last
    assert_equal "http://www.example.com/api/notes/#{note.id}", response.location
    assert_equal [ "Dave's", users(:dave), nil ], [ note.title, note.author, note.folder ]
    assert_equal 0, response.parsed_body["lock_version"]

    api :post, "/api/notes", as: users(:bob), params: { title: "Bob's", folder_id: folders(:engineering).id }
    assert_response :created
    assert_equal folders(:engineering), Note.last.folder
    assert_equal users(:bob), Note.last.author
  end

  test "creating a note ignores author_id and everyone_access, and saves a null body as empty" do
    api :post, "/api/notes", as: users(:dave), params: { title: "x", body: nil, author_id: users(:alice).id, everyone_access: "edit" }
    assert_response :created
    assert_equal [ users(:dave), "none", "" ], [ Note.last.author, Note.last.everyone_access, Note.last.body ]
  end

  test "creating a note inside a hidden folder is a 404, and in a view-only one a 403" do
    assert_no_difference -> { Note.count } do
      [ folders(:alice_folder).id, 0, "abc" ].each do |folder_id|
        api :post, "/api/notes", as: users(:dave), params: { title: "x", folder_id: folder_id }
        assert_api_not_found
      end
      api :post, "/api/notes", as: users(:carol), params: { title: "x", folder_id: folders(:alice_folder).id }
      assert_api_forbidden
    end
  end

  test "creating a note with errors or non-scalar params" do
    assert_no_difference -> { Note.count } do
      api :post, "/api/notes", as: users(:dave), params: { title: "" }
      assert_response :unprocessable_entity
      assert_equal [ "can't be blank" ], response.parsed_body.dig("errors", "title")

      # Checked before any lookup, so a hidden folder and a missing one look the same.
      [ [ folders(:alice_folder).id ], [ 0 ], { id: 1 } ].each do |folder_id|
        api :post, "/api/notes", as: users(:dave), params: { title: "x", folder_id: folder_id }
        assert_api_bad_request
      end
      api :post, "/api/notes", as: users(:dave), params: { title: [ "x" ] }
      assert_api_bad_request
    end
  end

  test "an editor changes only the fields sent" do
    note = notes(:eng_plan)
    api :patch, "/api/notes/#{note.id}", as: users(:bob), params: { body: "v2", lock_version: 0, folder_id: nil, author_id: users(:bob).id }
    assert_response :ok
    note.reload
    assert_equal [ "Eng plan", "v2", 1 ], [ note.title, note.body, note.lock_version ]
    assert_equal [ folders(:engineering), users(:alice) ], [ note.folder, note.author ]
    assert_equal 1, response.parsed_body["lock_version"]
  end

  test "updating a hidden note is a 404, and a view-only one a 403" do
    api :patch, "/api/notes/#{@note.id}", as: users(:dave), params: { title: "x", lock_version: 0 }
    assert_api_not_found
    api :patch, "/api/notes/#{@note.id}", as: users(:carol), params: { title: "x", lock_version: 0 }
    assert_api_forbidden
    assert_equal "Alice private", @note.reload.title
  end

  test "only the author changes everyone_access" do
    note = notes(:eng_plan)
    api :patch, "/api/notes/#{note.id}", as: users(:bob), params: { everyone_access: "view", lock_version: 0 }
    assert_api_forbidden
    assert_equal "none", note.reload.everyone_access

    api :patch, "/api/notes/#{note.id}", as: users(:alice), params: { everyone_access: "admin", lock_version: 0 }
    assert_response :unprocessable_entity
    assert response.parsed_body.dig("errors", "everyone_access").present?

    api :patch, "/api/notes/#{note.id}", as: users(:alice), params: { everyone_access: "view", lock_version: 0 }
    assert_response :ok
    assert_equal "view", note.reload.everyone_access
  end

  test "a stale or missing lock_version is a 409, a malformed one a 400" do
    note = notes(:eng_plan)
    api :patch, "/api/notes/#{note.id}", as: users(:alice), params: { body: "Alice's", lock_version: 0 }
    assert_response :ok

    api :patch, "/api/notes/#{note.id}", as: users(:bob), params: { body: "Bob's", lock_version: 0 }
    assert_response :conflict
    assert_equal({ "error" => "This note was changed by someone else." }, response.parsed_body)

    [ {}, { lock_version: nil }, { lock_version: "" } ].each do |lock|
      api :patch, "/api/notes/#{note.id}", as: users(:bob), params: { body: "Bob's" }.merge(lock)
      assert_response :conflict
    end
    [ "abc", [ 1 ], 1.5, "9" * 23, 9 * 10**22 ].each do |lock_version|
      api :patch, "/api/notes/#{note.id}", as: users(:bob), params: { body: "Bob's", lock_version: lock_version }
      assert_api_bad_request
    end
    assert_equal [ "Alice's", 1 ], [ note.reload.body, note.lock_version ]
  end

  test "validation errors on update are a 422" do
    api :patch, "/api/notes/#{@note.id}", as: users(:alice), params: { title: " ", lock_version: 0 }
    assert_response :unprocessable_entity
    assert_equal "Alice private", @note.reload.title
  end

  test "only the author deletes a note" do
    note = notes(:eng_plan)
    api :delete, "/api/notes/#{@note.id}", as: users(:dave)
    assert_api_not_found
    api :delete, "/api/notes/#{@note.id}", as: users(:carol)
    assert_api_forbidden
    api :delete, "/api/notes/#{note.id}", as: users(:bob)
    assert_api_forbidden
    assert Note.exists?(note.id)

    api :delete, "/api/notes/#{note.id}", as: users(:alice)
    assert_response :no_content
    assert_not Note.exists?(note.id)
  end
end
