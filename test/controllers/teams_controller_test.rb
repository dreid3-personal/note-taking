require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    patch current_user_path, params: { user_id: users(:dave).id }
  end

  test "index lists teams with their member counts and links" do
    get teams_path

    assert_response :success
    assert_select "td a[href=?]", team_path(teams(:engineering)), "Engineering"
    assert_select "tr", text: /Engineering\s*2/
    assert_select "tr", text: /Design\s*1/
    assert_select "form[action=?]", teams_path
    assert_select ".sidebar a.active", "👥 Teams"
  end

  test "create adds the team, its team folder and the creator as its first member" do
    assert_difference [ "Team.count", "Folder.count", "Membership.count" ], 1 do
      post teams_path, params: { team: { name: "  Marketing  " } }
    end

    team = Team.find_by!(name: "Marketing")
    assert_redirected_to team_path(team)
    assert_equal [ users(:dave) ], team.users
    assert_equal "Marketing", team.folder.name
    assert_equal users(:dave), team.folder.author

    follow_redirect!
    assert_select ".alert", "Team added."
    assert_select "td", "Dave"
  end

  test "create with a name already taken, ignoring case and spaces, shows the error" do
    [ "Engineering", "  engineering  " ].each do |name|
      assert_no_difference [ "Team.count", "Folder.count", "Membership.count" ] do
        post teams_path, params: { team: { name: name } }
      end

      assert_response :unprocessable_entity
      assert_select ".invalid-feedback", "Name has already been taken"
      assert_select "input.is-invalid[name='team[name]'][value=?]", name
      assert_select ".field_with_errors", count: 0
    end
  end

  test "create with a blank name shows the error" do
    assert_no_difference "Team.count" do
      post teams_path, params: { team: { name: "  " } }
    end

    assert_response :unprocessable_entity
    assert_select ".invalid-feedback", "Name can't be blank"
  end

  test "show lists members and offers only users not yet in the team" do
    get team_path(teams(:engineering))

    assert_response :success
    assert_select "h1", "Engineering"
    assert_select "a[href=?]", edit_team_path(teams(:engineering)), "Rename"
    assert_select "td", "Alice"
    assert_select "td", "Bob"
    assert_select "td", text: "Carol", count: 0
    assert_select "main select[name=user_id] option", text: "Alice", count: 0
    assert_select "main select[name=user_id] option", text: "Bob", count: 0
    assert_select "main select[name=user_id] option", "Carol"
    assert_select "main select[name=user_id] option", "Dave"
  end

  test "show says when everyone is already a member" do
    [ :alice, :bob, :dave ].each { |name| teams(:design).memberships.create!(user: users(name)) }
    get team_path(teams(:design))

    assert_select "main select[name=user_id]", count: 0
    assert_select "p", "Everyone is already a member."
  end

  test "edit shows the rename form" do
    get edit_team_path(teams(:engineering))

    assert_response :success
    assert_select "input[name='team[name]'][value=?]", "Engineering"
  end

  test "update renames the team and its team folder" do
    patch team_path(teams(:engineering)), params: { team: { name: "Growth" } }

    assert_redirected_to team_path(teams(:engineering))
    assert_equal "Growth", teams(:engineering).reload.name
    assert_equal "Growth", folders(:engineering).reload.name
    follow_redirect!
    assert_select ".alert", "Team renamed."
    assert_select "h1", "Growth"
  end

  test "update with a name already taken is rejected and changes nothing" do
    patch team_path(teams(:engineering)), params: { team: { name: " design " } }

    assert_response :unprocessable_entity
    assert_select ".invalid-feedback", "Name has already been taken"
    assert_select "h1", "Rename Engineering"
    assert_equal "Engineering", teams(:engineering).reload.name
    assert_equal "Engineering", folders(:engineering).reload.name
  end

  test "update with a blank name is rejected" do
    patch team_path(teams(:engineering)), params: { team: { name: "" } }

    assert_response :unprocessable_entity
    assert_select ".invalid-feedback", "Name can't be blank"
    assert_equal "Engineering", teams(:engineering).reload.name
  end

  test "every page and action redirects to the Notes page without a current user" do
    patch current_user_path, params: { user_id: "" }
    team = teams(:engineering)

    get teams_path
    assert_redirected_to root_path
    assert_response :see_other
    get team_path(team)
    assert_redirected_to root_path
    get edit_team_path(team)
    assert_redirected_to root_path

    assert_no_difference "Team.count" do
      post teams_path, params: { team: { name: "Marketing" } }
    end
    assert_redirected_to root_path

    patch team_path(team), params: { team: { name: "Growth" } }
    assert_redirected_to root_path
    assert_equal "Engineering", team.reload.name
  end
end
