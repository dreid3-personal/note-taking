require "test_helper"

class TeamCreateWithFolderTest < ActiveSupport::TestCase
  test "creates the team, its team folder and the creator's membership" do
    alice = users(:alice)

    team = Team.create_with_folder(name: "  Marketing ", creator: alice)

    assert team.persisted?
    assert_equal "Marketing", team.name
    assert_equal [ alice ], team.users

    folder = team.folder
    assert folder.persisted?
    assert folder.team_folder?
    assert_equal "Marketing", folder.name
    assert_equal alice, folder.author
    assert_nil folder.parent
    assert folder.everyone_none?
  end

  test "saves nothing when the team is invalid" do
    assert_no_difference [ "Team.count", "Folder.count", "Membership.count" ] do
      team = Team.create_with_folder(name: "engineering", creator: users(:alice))

      assert_not team.persisted?
      assert_includes team.errors[:name], "has already been taken"
    end
  end

  test "saves nothing when the team folder can't be created" do
    assert_no_difference [ "Team.count", "Folder.count", "Membership.count" ] do
      team = Team.create_with_folder(name: "Marketing", creator: nil)

      assert_not team.persisted?
      assert_includes team.errors[:base], "Author must exist"
    end
  end
end
