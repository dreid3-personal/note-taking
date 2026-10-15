require "test_helper"

# /api/users, /api/teams and /api/teams/:team_id/members. Like the HTML pages, any user may see
# and manage any team, so there is no 403 or hidden-record 404 here; only the current user matters.
class Api::UsersAndTeamsTest < ActionDispatch::IntegrationTest
  test "users can be listed and added without a current user" do
    api :get, "/api/users"
    assert_response :ok
    assert_equal %w[Alice Bob Carol Dave], response.parsed_body.pluck("name")

    assert_difference -> { User.count } do
      api :post, "/api/users", params: { name: " Erin ", email: " ERIN@Example.com " }
    end
    assert_response :created
    erin = User.last
    assert_equal "http://www.example.com/api/users/#{erin.id}", response.location
    assert_equal({ "id" => erin.id, "name" => "Erin", "email" => "erin@example.com" }, response.parsed_body)
  end

  test "adding a user with errors is a 422 with the errors" do
    assert_no_difference -> { User.count } do
      api :post, "/api/users", params: { name: "", email: "ALICE@example.com" }
    end
    assert_response :unprocessable_entity
    assert_equal [ "can't be blank" ], response.parsed_body.dig("errors", "name")
    assert_equal [ "has already been taken" ], response.parsed_body.dig("errors", "email")
  end

  test "a non-scalar or malformed body is a 400" do
    assert_no_difference -> { User.count } do
      api :post, "/api/users", params: { name: [ "Erin" ], email: "erin@example.com" }
      assert_api_bad_request
      api :post, "/api/users", params: { name: { a: 1 }, email: "erin@example.com" }
      assert_api_bad_request
      post "/api/users", params: "{not json", headers: { "Content-Type" => "application/json" }
      assert_api_bad_request
    end
  end

  test "one user needs a current user" do
    api :get, "/api/users/#{users(:bob).id}"
    assert_api_unauthorized

    api :get, "/api/users/#{users(:bob).id}", as: users(:alice)
    assert_response :ok
    assert_equal "bob@example.com", response.parsed_body["email"]

    api :get, "/api/users/0", as: users(:alice)
    assert_api_not_found
  end

  test "an unknown or malformed X-User-Id is a 401" do
    [ "0", "abc", "#{users(:alice).id}abc", "" ].each do |id|
      get "/api/home", headers: { "X-User-Id" => id }
      assert_api_unauthorized
    end
  end

  test "teams need a current user" do
    team = teams(:engineering)
    api :get, "/api/teams"
    assert_api_unauthorized
    api :get, "/api/teams/#{team.id}"
    assert_api_unauthorized
    assert_no_difference -> { Team.count } do
      api :post, "/api/teams", params: { name: "Sales" }
    end
    assert_api_unauthorized
    api :patch, "/api/teams/#{team.id}", params: { name: "Platform" }
    assert_api_unauthorized
    assert_equal "Engineering", team.reload.name
    assert_no_difference -> { Membership.count } do
      api :post, "/api/teams/#{team.id}/members", params: { user_id: users(:dave).id }
      assert_api_unauthorized
      api :delete, "/api/teams/#{team.id}/members/#{users(:bob).id}"
      assert_api_unauthorized
    end
  end

  test "teams are listed and shown with their members" do
    api :get, "/api/teams", as: users(:dave)
    assert_response :ok
    assert_equal %w[Design Engineering], response.parsed_body.pluck("name")

    api :get, "/api/teams/#{teams(:engineering).id}", as: users(:dave)
    assert_response :ok
    assert_equal %w[Alice Bob], response.parsed_body["members"].pluck("name")

    api :get, "/api/teams/0", as: users(:dave)
    assert_api_not_found
  end

  test "creating a team creates its folder, with the creator as a member" do
    api :post, "/api/teams", as: users(:dave), params: { name: "Sales" }
    assert_response :created
    team = Team.find_by!(name: "Sales")
    assert_equal "http://www.example.com/api/teams/#{team.id}", response.location
    assert_equal [ "Dave" ], response.parsed_body["members"].pluck("name")
    assert_equal "Sales", team.folder.name

    api :post, "/api/teams", as: users(:dave), params: { name: "sales" }
    assert_response :unprocessable_entity
    assert_equal [ "has already been taken" ], response.parsed_body.dig("errors", "name")
  end

  test "renaming a team renames its folder" do
    team = teams(:engineering)
    api :patch, "/api/teams/#{team.id}", as: users(:dave), params: { name: "Platform" }
    assert_response :ok
    assert_equal "Platform", team.folder.reload.name

    api :patch, "/api/teams/#{team.id}", as: users(:dave), params: { name: "" }
    assert_response :unprocessable_entity
    api :patch, "/api/teams/#{team.id}", as: users(:dave), params: { name: [ "x" ] }
    assert_api_bad_request
    assert_equal "Platform", team.reload.name
  end

  test "members are added and removed" do
    team = teams(:engineering)
    api :post, "/api/teams/#{team.id}/members", as: users(:dave), params: { user_id: users(:carol).id }
    assert_response :created
    assert_includes team.users.reload, users(:carol)

    api :post, "/api/teams/#{team.id}/members", as: users(:dave), params: { user_id: users(:carol).id }
    assert_response :unprocessable_entity
    api :post, "/api/teams/#{team.id}/members", as: users(:dave), params: { user_id: 0 }
    assert_response :unprocessable_entity
    api :post, "/api/teams/#{team.id}/members", as: users(:dave), params: { user_id: [ users(:dave).id ] }
    assert_api_bad_request
    assert_not_includes team.users.reload, users(:dave)

    api :delete, "/api/teams/#{team.id}/members/#{users(:carol).id}", as: users(:dave)
    assert_response :no_content
    assert_not_includes team.users.reload, users(:carol)

    api :delete, "/api/teams/#{team.id}/members/#{users(:carol).id}", as: users(:dave)
    assert_api_not_found
  end
end
