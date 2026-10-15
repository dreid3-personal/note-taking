require "test_helper"

class MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    patch current_user_path, params: { user_id: users(:dave).id }
  end

  test "create adds a member" do
    team = teams(:engineering)

    assert_difference "team.memberships.count", 1 do
      post team_memberships_path(team), params: { user_id: users(:carol).id }
    end

    assert_redirected_to team_path(team)
    assert_includes team.users.reload, users(:carol)
    follow_redirect!
    assert_select ".alert", "Carol added."
    assert_select "td", "Carol"
    assert_select "main select[name=user_id] option", text: "Carol", count: 0
  end

  test "create with an existing member or no user shows an error" do
    team = teams(:engineering)

    assert_no_difference "Membership.count" do
      post team_memberships_path(team), params: { user_id: users(:alice).id }
    end
    assert_redirected_to team_path(team)
    follow_redirect!
    assert_select ".alert-danger", "User is already a member of this team"

    assert_no_difference "Membership.count" do
      post team_memberships_path(team), params: { user_id: "" }
    end
    follow_redirect!
    assert_select ".alert-danger", "User must exist"
  end

  test "create when the unique index catches a duplicate the validation missed, as in a double submit" do
    team = teams(:engineering)
    new_membership = Membership.method(:new)
    Membership.define_singleton_method(:new) do |*args, **options, &block|
      new_membership.call(*args, **options, &block).tap { |membership| def membership.valid?(*) = true }
    end

    assert_no_difference "Membership.count" do
      post team_memberships_path(team), params: { user_id: users(:alice).id }
    end
    assert_redirected_to team_path(team)
    follow_redirect!
    assert_select ".alert-danger", "User is already a member of this team"
  ensure
    Membership.singleton_class.remove_method(:new)
  end

  test "destroy removes a member" do
    team = teams(:engineering)

    assert_difference "team.memberships.count", -1 do
      delete team_membership_path(team, memberships(:bob_engineering))
    end

    assert_redirected_to team_path(team)
    assert_not_includes team.users.reload, users(:bob)
    follow_redirect!
    assert_select ".alert", "Bob removed."
    assert_select "td", text: "Bob", count: 0
    assert_select "main select[name=user_id] option", "Bob"
  end

  test "destroy only removes memberships of the team in the URL" do
    assert_no_difference "Membership.count" do
      delete team_membership_path(teams(:engineering), memberships(:carol_design))
    end

    assert_response :not_found
  end

  test "adding and removing members redirects to the Notes page without a current user" do
    patch current_user_path, params: { user_id: "" }
    team = teams(:engineering)

    assert_no_difference "Membership.count" do
      post team_memberships_path(team), params: { user_id: users(:carol).id }
    end
    assert_redirected_to root_path

    assert_no_difference "Membership.count" do
      delete team_membership_path(team, memberships(:bob_engineering))
    end
    assert_redirected_to root_path
  end
end
