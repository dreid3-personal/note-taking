require "test_helper"

# /api/notes/:note_id/shares, /api/folders/:folder_id/shares and /api/shares/:id. Only the item's
# author may use them, never for a team folder. In the fixtures, Alice private is shared with Carol
# for viewing, and Alice folder with the Design team (Carol) for viewing.
class Api::SharesTest < ActionDispatch::IntegrationTest
  setup do
    @note = notes(:alice_private)
    @share = shares(:alice_private_carol)
  end

  test "every shares endpoint needs a current user" do
    api :get, "/api/notes/#{@note.id}/shares"
    assert_api_unauthorized
    api :get, "/api/folders/#{folders(:alice_folder).id}/shares"
    assert_api_unauthorized
    assert_no_difference -> { Share.count } do
      api :post, "/api/notes/#{@note.id}/shares", params: { email: "dave@example.com", access: "view" }
      assert_api_unauthorized
      api :post, "/api/folders/#{folders(:alice_folder).id}/shares", params: { email: "dave@example.com", access: "view" }
      assert_api_unauthorized
      api :delete, "/api/shares/#{@share.id}"
      assert_api_unauthorized
    end
    api :patch, "/api/shares/#{@share.id}", params: { access: "edit" }
    assert_api_unauthorized
    assert_equal "view", @share.reload.access
  end

  test "the author lists a note's sharing settings" do
    api :get, "/api/notes/#{@note.id}/shares", as: users(:alice)
    assert_response :ok
    assert_equal "none", response.parsed_body["everyone_access"]
    assert_equal [ { "id" => @share.id, "access" => "view", "note_id" => @note.id, "folder_id" => nil,
      "user" => { "id" => users(:carol).id, "name" => "Carol", "email" => "carol@example.com" }, "team" => nil } ],
      response.parsed_body["shares"]
    assert_equal [], response.parsed_body["inherited"]
  end

  test "a folder's shares list what it inherits from the folders above it" do
    folders(:alice_folder).update!(everyone_access: :view)
    api :get, "/api/folders/#{folders(:alice_subfolder).id}/shares", as: users(:alice)
    assert_response :ok
    assert_equal [ [ "everyone", nil, "view", "Alice folder" ], [ "team", "Design", "view", "Alice folder" ] ],
      response.parsed_body["inherited"].map { |grant| [ grant.dig("grantee", "type"), grant.dig("grantee", "name"), grant["access"], grant.dig("folder", "name") ] }
  end

  test "sharing settings are a 404 without access and a 403 for anyone but the author" do
    [ "/api/notes/#{@note.id}/shares", "/api/folders/#{folders(:alice_folder).id}/shares" ].each do |path|
      api :get, path, as: users(:dave)
      assert_api_not_found
      api :post, path, as: users(:dave), params: { email: "dave@example.com", access: "edit" }
      assert_api_not_found
      api :get, path, as: users(:carol)
      assert_api_forbidden
      api :post, path, as: users(:carol), params: { email: "carol@example.com", access: "edit" }
      assert_api_forbidden
    end
    api :get, "/api/notes/0/shares", as: users(:dave)
    assert_api_not_found
    api :get, "/api/notes/#{notes(:eng_plan).id}/shares", as: users(:bob)
    assert_api_forbidden
    assert_equal 2, Share.count
  end

  test "a team folder can't be shared, even by its creator" do
    path = "/api/folders/#{folders(:engineering).id}/shares"
    api :get, path, as: users(:alice)
    assert_api_forbidden
    api :post, path, as: users(:alice), params: { team_id: teams(:design).id, access: "view" }
    assert_api_forbidden
    api :get, path, as: users(:carol)
    assert_api_not_found
    assert_equal 2, Share.count
  end

  test "sharing with a user by email, normalized" do
    api :post, "/api/notes/#{@note.id}/shares", as: users(:alice), params: { email: "  DAVE@Example.com ", access: "edit" }
    assert_response :created
    share = Share.last
    assert_equal "http://www.example.com/api/shares/#{share.id}", response.location
    assert_equal [ users(:dave), "edit" ], [ share.user, share.access ]
    assert_equal "Dave", response.parsed_body.dig("user", "name")
  end

  test "sharing a folder with a team" do
    api :post, "/api/folders/#{folders(:empty_folder).id}/shares", as: users(:alice), params: { team_id: teams(:design).id.to_s, access: "view" }
    assert_response :created
    assert_equal [ teams(:design), folders(:empty_folder) ], [ Share.last.team, Share.last.folder ]
  end

  test "bad shares are a 422 or a 400" do
    path = "/api/notes/#{@note.id}/shares"
    assert_no_difference -> { Share.count } do
      {
        { access: "view" } => "base",
        { email: "dave@example.com", team_id: teams(:design).id, access: "view" } => "base",
        { email: "nobody@example.com", access: "view" } => "email",
        { email: "alice@example.com", access: "view" } => "email",
        { team_id: 0, access: "view" } => "team_id",
        { team_id: "abc", access: "view" } => "team_id",
        { email: "carol@example.com", access: "view" } => "user_id",
        { email: "dave@example.com", access: "admin" } => "access",
        { email: "dave@example.com" } => "access"
      }.each do |params, field|
        api :post, path, as: users(:alice), params: params
        assert_response :unprocessable_entity, params.inspect
        assert response.parsed_body.dig("errors", field).present?, "#{params.inspect}: #{response.body}"
      end

      [ { email: [ "dave@example.com" ], access: "view" }, { team_id: [ 1 ], access: "view" }, { email: "dave@example.com", access: [ "view" ] } ].each do |params|
        api :post, path, as: users(:alice), params: params
        assert_api_bad_request
      end
    end
  end

  test "only the author changes or removes a share" do
    Share.create!(note: @note, user: users(:bob), access: :edit)
    api :patch, "/api/shares/#{@share.id}", as: users(:dave), params: { access: "edit" }
    assert_api_not_found
    api :delete, "/api/shares/#{@share.id}", as: users(:dave)
    assert_api_not_found
    api :patch, "/api/shares/#{@share.id}", as: users(:bob), params: { access: "edit" }
    assert_api_forbidden
    api :delete, "/api/shares/#{@share.id}", as: users(:bob)
    assert_api_forbidden
    api :patch, "/api/shares/0", as: users(:alice), params: { access: "edit" }
    assert_api_not_found
    assert_equal "view", @share.reload.access

    api :patch, "/api/shares/#{@share.id}", as: users(:alice), params: { access: "admin" }
    assert_response :unprocessable_entity
    api :patch, "/api/shares/#{@share.id}", as: users(:alice), params: {}
    assert_api_bad_request
    api :patch, "/api/shares/#{@share.id}", as: users(:alice), params: { access: [ "edit" ] }
    assert_api_bad_request

    api :patch, "/api/shares/#{@share.id}", as: users(:alice), params: { access: "edit", user_id: users(:dave).id }
    assert_response :ok
    assert_equal [ "edit", users(:carol) ], [ @share.reload.access, @share.user ]

    api :delete, "/api/shares/#{@share.id}", as: users(:alice)
    assert_response :no_content
    assert_not Share.exists?(@share.id)
  end
end
