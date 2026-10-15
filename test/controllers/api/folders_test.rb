require "test_helper"

# /api/folders. In the fixtures, Alice folder (holding Alice subfolder and Alice nested) is shared
# with the Design team (Carol) for viewing; Engineering is Alice and Bob's team folder. Dave has
# access to none of them.
class Api::FoldersTest < ActionDispatch::IntegrationTest
  setup do
    @folder = folders(:alice_folder)
  end

  test "every folders endpoint needs a current user" do
    api :get, "/api/folders"
    assert_api_unauthorized
    api :get, "/api/folders/#{@folder.id}"
    assert_api_unauthorized
    assert_no_difference -> { Folder.count } do
      api :post, "/api/folders", params: { name: "New" }
      assert_api_unauthorized
      api :delete, "/api/folders/#{folders(:empty_folder).id}"
      assert_api_unauthorized
    end
    api :patch, "/api/folders/#{@folder.id}", params: { name: "Changed" }
    assert_api_unauthorized
    assert_equal "Alice folder", @folder.reload.name
  end

  test "the folders index lists only folders the user can open" do
    api :get, "/api/folders", as: users(:carol)
    assert_response :ok
    assert_equal [ "Alice folder", "Alice subfolder", "Design" ], response.parsed_body.pluck("name")

    api :get, "/api/folders", as: users(:dave)
    assert_equal [], response.parsed_body
  end

  test "showing a folder includes its children, folders first" do
    api :get, "/api/folders/#{@folder.id}", as: users(:carol)
    assert_response :ok
    assert_equal "view", response.parsed_body["access"]
    assert_equal [ [ "folder", "Alice subfolder" ], [ "note", "Alice nested" ] ],
      response.parsed_body["children"].map { |item| [ item["type"], item["name"] || item["title"] ] }
  end

  test "a hidden folder is a 404 identical to a missing one" do
    api :get, "/api/folders/0", as: users(:dave)
    missing = response.body
    [ @folder.id, folders(:engineering).id ].each do |id|
      api :get, "/api/folders/#{id}", as: users(:dave)
      assert_api_not_found
      assert_equal missing, response.body
    end
  end

  test "creating a folder at the top level or inside a folder the user can edit" do
    api :post, "/api/folders", as: users(:dave), params: { name: "Dave's" }
    assert_response :created
    folder = Folder.last
    assert_equal "http://www.example.com/api/folders/#{folder.id}", response.location
    assert_equal [ users(:dave), nil ], [ folder.author, folder.parent ]
    assert_equal [], response.parsed_body["children"]

    api :post, "/api/folders", as: users(:bob), params: { name: "Bob's", parent_id: folders(:engineering).id.to_s }
    assert_response :created
    assert_equal folders(:engineering), Folder.last.parent
  end

  test "creating a folder inside a hidden folder is a 404, and in a view-only one a 403" do
    assert_no_difference -> { Folder.count } do
      [ @folder.id, 0 ].each do |parent_id|
        api :post, "/api/folders", as: users(:dave), params: { name: "x", parent_id: parent_id }
        assert_api_not_found
      end
      api :post, "/api/folders", as: users(:carol), params: { name: "x", parent_id: @folder.id }
      assert_api_forbidden
      api :post, "/api/folders", as: users(:dave), params: { name: "x", parent_id: [ @folder.id ] }
      assert_api_bad_request
      api :post, "/api/folders", as: users(:dave), params: { name: "" }
      assert_response :unprocessable_entity
    end
  end

  test "renaming needs edit access, and never a team folder" do
    api :patch, "/api/folders/#{@folder.id}", as: users(:dave), params: { name: "x" }
    assert_api_not_found
    api :patch, "/api/folders/#{@folder.id}", as: users(:carol), params: { name: "x" }
    assert_api_forbidden
    api :patch, "/api/folders/#{folders(:engineering).id}", as: users(:alice), params: { name: "x" }
    assert_api_forbidden
    assert_equal [ "Alice folder", "Engineering" ], [ @folder.reload.name, folders(:engineering).reload.name ]

    api :patch, "/api/folders/#{@folder.id}", as: users(:alice), params: { name: "Renamed", parent_id: nil }
    assert_response :ok
    assert_equal "Renamed", @folder.reload.name

    api :patch, "/api/folders/#{@folder.id}", as: users(:alice), params: { name: "" }
    assert_response :unprocessable_entity
    api :patch, "/api/folders/#{@folder.id}", as: users(:alice), params: { name: { a: 1 } }
    assert_api_bad_request
  end

  test "only the author changes everyone_access, never on a team folder" do
    Share.create!(folder: @folder, user: users(:bob), access: :edit)
    api :patch, "/api/folders/#{@folder.id}", as: users(:bob), params: { everyone_access: "view" }
    assert_api_forbidden
    api :patch, "/api/folders/#{folders(:engineering).id}", as: users(:alice), params: { everyone_access: "view" }
    assert_api_forbidden
    assert_equal [ "none", "none" ], [ @folder.reload.everyone_access, folders(:engineering).reload.everyone_access ]

    api :patch, "/api/folders/#{@folder.id}", as: users(:alice), params: { everyone_access: "edit" }
    assert_response :ok
    assert_equal "edit", @folder.reload.everyone_access
  end

  test "only the author deletes a folder, only when it's empty, and never a team folder" do
    empty = folders(:empty_folder)
    Share.create!(folder: empty, user: users(:carol), access: :edit)
    api :delete, "/api/folders/#{empty.id}", as: users(:dave)
    assert_api_not_found
    api :delete, "/api/folders/#{empty.id}", as: users(:carol)
    assert_api_forbidden
    api :delete, "/api/folders/#{folders(:engineering).id}", as: users(:alice)
    assert_api_forbidden

    api :delete, "/api/folders/#{@folder.id}", as: users(:alice)
    assert_response :unprocessable_entity
    assert_equal [ "Move or delete everything inside this folder first." ], response.parsed_body.dig("errors", "base")
    assert Folder.exists?(@folder.id)

    api :delete, "/api/folders/#{empty.id}", as: users(:alice)
    assert_response :no_content
    assert_not Folder.exists?(empty.id)
  end
end
