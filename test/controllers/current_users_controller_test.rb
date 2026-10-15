require "test_helper"

class CurrentUsersControllerTest < ActionDispatch::IntegrationTest
  test "switching stores the user and redirects back" do
    patch current_user_path, params: { user_id: users(:bob).id }, headers: { "HTTP_REFERER" => users_url }

    assert_redirected_to users_url
    assert_response :see_other
    follow_redirect!
    assert_select "select[name=user_id] option[selected]", "Bob"
  end

  test "switching without a referer goes to the Notes page" do
    patch current_user_path, params: { user_id: users(:bob).id }

    assert_redirected_to root_path
  end

  test "a referer on another host redirects to the Notes page instead" do
    patch current_user_path, params: { user_id: users(:bob).id }, headers: { "HTTP_REFERER" => "https://evil.example/x" }

    assert_redirected_to root_url
  end

  test "picking the blank option clears the current user" do
    patch current_user_path, params: { user_id: users(:bob).id }
    patch current_user_path, params: { user_id: "" }
    get root_path

    assert_select "p", "Pick a user in the sidebar to get started."
  end

  test "a current user who no longer exists is cleared" do
    patch current_user_path, params: { user_id: users(:dave).id }
    users(:dave).destroy
    get root_path

    assert_select "p", "Pick a user in the sidebar to get started."
    assert_nil session[:user_id]
  end
end
