require "test_helper"

# The core of E2E 1 (privacy) in TEST_PLAN.md, scripted over /api only: every person, team, note,
# folder and share is made through the API, starting from an empty database. "Hidden" means the
# item is in no /api/home section and its URLs give the same 404 as a record that doesn't exist.
class ApiPrivacyTest < ActionDispatch::IntegrationTest
  setup do
    [ Share, Note, Membership, Folder, Team, User ].each(&:delete_all)
  end

  test "the core privacy scenarios" do
    alice, bob, carol, dave = %w[Alice Bob Carol Dave].map do |name|
      create(:post, "/api/users", nil, name: name, email: "#{name.downcase}@example.com")
      User.find(response.parsed_body["id"])
    end

    # 1.0 Teams: Engineering is Alice and Bob, Design is Carol.
    engineering = create(:post, "/api/teams", alice, name: "Engineering")["id"]
    create(:post, "/api/teams/#{engineering}/members", alice, user_id: bob.id)
    design = create(:post, "/api/teams", carol, name: "Design")["id"]
    eng_folder = home(alice)["team_folders"].first["id"]

    # 1.1 Private notes stay private.
    private_note = create(:post, "/api/notes", alice, title: "Alice private", body: "# Hi")["id"]
    alice_folder = create(:post, "/api/folders", alice, name: "Alice folder")["id"]
    nested = create(:post, "/api/notes", alice, title: "Alice nested", folder_id: alice_folder)["id"]
    assert_equal [ "Alice folder", "Alice private" ], titles(home(alice)["my_notes"])
    [ bob, dave ].each do |user|
      assert_hidden user, "/api/notes/#{private_note}", "/api/folders/#{alice_folder}", "/api/notes/#{nested}"
    end

    # 1.2 Team folders: visible only to members, including after leaving and rejoining.
    eng_plan = create(:post, "/api/notes", alice, title: "Eng plan", body: "v1", folder_id: eng_folder)["id"]
    assert_equal [ "Engineering" ], titles(home(bob)["team_folders"])
    assert_equal [ "Eng plan" ], titles(get_json(bob, "/api/folders/#{eng_folder}")["children"])
    edit_note(bob, eng_plan, body: "v2")
    assert_response :ok
    api :delete, "/api/folders/#{eng_folder}", as: alice
    assert_api_forbidden
    assert_hidden carol, "/api/folders/#{eng_folder}", "/api/notes/#{eng_plan}"

    api :delete, "/api/teams/#{engineering}/members/#{bob.id}", as: alice
    assert_response :no_content
    assert_hidden bob, "/api/folders/#{eng_folder}", "/api/notes/#{eng_plan}"
    create(:post, "/api/teams/#{engineering}/members", alice, user_id: bob.id)
    assert_equal [ "Engineering" ], titles(home(bob)["team_folders"])
    assert_equal "v2", get_json(bob, "/api/notes/#{eng_plan}")["body"]

    # 1.3 Sharing with a user, then lowering edit to view, then removing it.
    share = create(:post, "/api/notes/#{private_note}/shares", alice, email: "  CAROL@Example.com ", access: "view")["id"]
    assert_equal [ "Alice private" ], titles(home(carol)["shared_with_me"])
    edit_note(carol, private_note, title: "Carol's")
    assert_api_forbidden
    api :patch, "/api/shares/#{share}", as: alice, params: { access: "edit" }
    assert_response :ok
    edit_note(carol, private_note, body: "Carol was here")
    assert_response :ok
    api :patch, "/api/shares/#{share}", as: alice, params: { access: "view" }
    edit_note(carol, private_note, body: "Again")
    assert_api_forbidden
    api :get, "/api/notes/#{private_note}/shares", as: carol
    assert_api_forbidden
    api :delete, "/api/shares/#{share}", as: alice
    assert_response :no_content
    assert_hidden carol, "/api/notes/#{private_note}"
    assert_hidden dave, "/api/notes/#{private_note}"

    # 1.4 A team share inherited through a folder.
    create(:post, "/api/folders/#{alice_folder}/shares", alice, team_id: design, access: "view")
    assert_equal [ "Alice folder" ], titles(home(carol)["shared_with_me"])
    assert_equal "view", get_json(carol, "/api/notes/#{nested}")["access"]
    edit_note(carol, nested, body: "x")
    assert_api_forbidden
    inherited = get_json(alice, "/api/notes/#{nested}/shares")["inherited"]
    assert_equal [ [ "team", "Design", "view", "Alice folder" ] ],
      inherited.map { |grant| [ grant.dig("grantee", "type"), grant.dig("grantee", "name"), grant["access"], grant.dig("folder", "name") ] }
    assert_hidden dave, "/api/folders/#{alice_folder}", "/api/notes/#{nested}"
    create(:post, "/api/teams/#{design}/members", carol, user_id: dave.id)
    assert_equal "Alice nested", get_json(dave, "/api/notes/#{nested}")["title"]
    api :delete, "/api/teams/#{design}/members/#{dave.id}", as: carol
    assert_hidden dave, "/api/folders/#{alice_folder}", "/api/notes/#{nested}"

    # 1.5 Everyone: only the author changes it.
    edit_note(bob, eng_plan, everyone_access: "view")
    assert_api_forbidden
    edit_note(alice, private_note, everyone_access: "view")
    assert_response :ok
    assert_equal [ "Alice private" ], titles(home(dave)["shared_with_me"])
    edit_note(dave, private_note, body: "Dave's")
    assert_api_forbidden
    edit_note(alice, private_note, everyone_access: "none")
    assert_hidden dave, "/api/notes/#{private_note}"

    # 1.6 Two people editing at once: the second save gets a 409 and changes nothing.
    lock_version = get_json(bob, "/api/notes/#{eng_plan}")["lock_version"]
    api :patch, "/api/notes/#{eng_plan}", as: alice, params: { body: "Alice's", lock_version: lock_version }
    assert_response :ok
    api :patch, "/api/notes/#{eng_plan}", as: bob, params: { body: "Bob's", lock_version: lock_version }
    assert_response :conflict
    assert_equal "Alice's", get_json(bob, "/api/notes/#{eng_plan}")["body"]
  end

  private
    def create(method, path, user, params)
      api method, path, as: user, params: params
      assert_response :created, "#{path}: #{response.body}"
      response.parsed_body
    end

    def get_json(user, path)
      api :get, path, as: user
      assert_response :ok, path
      response.parsed_body
    end

    def home(user)
      get_json(user, "/api/home")
    end

    def titles(items)
      items.map { |item| item["name"] || item["title"] }
    end

    # Reads the note as the user, then sends its current lock_version along with the changes.
    def edit_note(user, id, changes)
      lock_version = get_json(user, "/api/notes/#{id}")["lock_version"]
      api :patch, "/api/notes/#{id}", as: user, params: changes.merge(lock_version: lock_version)
    end

    # Hidden from the user: listed nowhere on their home, and every URL (plus /shares) is the same
    # 404 as a missing record.
    def assert_hidden(user, *paths)
      listed = home(user).values.flatten.map { |item| "/api/#{item["type"]}s/#{item["id"]}" }
      paths.each do |path|
        assert_not_includes listed, path
        [ path, "#{path}/shares" ].each do |url|
          api :get, url, as: user
          assert_api_not_found
        end
      end
    end
end
