require "test_helper"

class NotesControllerTest < ActionDispatch::IntegrationTest
  test "with no current user, the Notes page asks to pick one" do
    get root_path

    assert_response :success
    assert_select "p", "Pick a user in the sidebar to get started."
    assert_select "a[href=?]", users_path, text: /Add one/, count: 0
    assert_select "select[name=user_id] option", "Alice"
  end

  test "with no users at all, the Notes page links to the Users page" do
    [ Share, Note, Folder, Membership, Team, User ].each(&:delete_all)
    get root_path

    assert_select "p", "Pick a user in the sidebar to get started."
    assert_select "a[href=?]", users_path, text: "Add one on the Users page"
  end

  test "with a current user, the message is gone" do
    patch current_user_path, params: { user_id: users(:alice).id }
    get root_path

    assert_select "p", text: "Pick a user in the sidebar to get started.", count: 0
  end

  test "the Notes link is highlighted on the Notes page, and the Users link on the Users page" do
    get root_path
    assert_select ".sidebar a.active", "📄 Notes"

    get users_path
    assert_select ".sidebar a.active", "👤 Users"
  end
end
