require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "index lists users without a current user" do
    get users_path

    assert_response :success
    assert_select "td", "Alice"
    assert_select "td", "alice@example.com"
    assert_select "form[action=?]", users_path
  end

  test "create adds a user and redirects to the list" do
    assert_difference "User.count", 1 do
      post users_path, params: { user: { name: "Erin", email: "erin@example.com" } }
    end

    assert_redirected_to users_path
    follow_redirect!
    assert_select ".alert", "User added."
    assert_select "td", "Erin"
    assert_select "option", "Erin"
  end

  test "create with a duplicate email shows the error and keeps what was typed" do
    assert_no_difference "User.count" do
      post users_path, params: { user: { name: "Alice Two", email: "  ALICE@Example.COM  " } }
    end

    assert_response :unprocessable_entity
    assert_select ".invalid-feedback", "Email has already been taken"
    assert_select "input[name='user[name]'][value=?]", "Alice Two"
    assert_select "input[name='user[email]'][value=?]", "  ALICE@Example.COM  "
  end

  test "create with blank fields shows an error next to each" do
    assert_no_difference "User.count" do
      post users_path, params: { user: { name: " ", email: "" } }
    end

    assert_response :unprocessable_entity
    assert_select ".invalid-feedback", "Name can't be blank"
    assert_select ".invalid-feedback", "Email can't be blank"
    # Bootstrap only shows the feedback when it follows the invalid field directly.
    assert_select ".field_with_errors", count: 0
    assert_select "input.is-invalid ~ .invalid-feedback", count: 2
  end

  test "create with an over-long name shows the error, and the fields have a maxlength" do
    assert_no_difference "User.count" do
      post users_path, params: { user: { name: "a" * 101, email: "long@example.com" } }
    end

    assert_response :unprocessable_entity
    assert_select "input.is-invalid ~ .invalid-feedback", "Name is too long (maximum is 100 characters)"
    assert_select "input[name='user[name]'][maxlength='100']"
    assert_select "input[name='user[email]'][maxlength='254']"
  end
end
