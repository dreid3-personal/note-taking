require "test_helper"

class TeamTest < ActiveSupport::TestCase
  test "requires a name" do
    team = Team.new(name: "  ")

    assert_not team.valid?
    assert_includes team.errors[:name], "can't be blank"
  end

  test "trims the name" do
    assert_equal "Marketing", Team.new(name: "  Marketing ").name
  end

  test "rejects a duplicate name on create, ignoring case and spaces" do
    [ "Engineering", "engineering", "  ENGINEERING  " ].each do |name|
      team = Team.new(name: name)

      assert_not team.valid?, "#{name.inspect} should be rejected"
      assert_includes team.errors[:name], "has already been taken"
    end
  end

  test "rejects a duplicate name on rename, ignoring case and spaces" do
    team = teams(:design)

    assert_not team.update(name: " engineering ")
    assert_includes team.errors[:name], "has already been taken"
    assert_equal "Design", team.reload.name
  end

  test "the unique index rejects a duplicate name even when validation is skipped" do
    team = Team.new(name: "ENGINEERING")

    assert_raises(ActiveRecord::RecordNotUnique) { team.save!(validate: false) }
  end

  test "renaming also renames the team folder" do
    team = teams(:engineering)

    team.update!(name: "Growth")

    assert_equal "Growth", folders(:engineering).reload.name
  end

  test "a failed rename leaves the team folder's name alone" do
    team = teams(:engineering)

    assert_not team.update(name: "Design")
    assert_equal "Engineering", folders(:engineering).reload.name
  end
end
