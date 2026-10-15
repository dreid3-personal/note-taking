require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  test "a user can be added to a team" do
    assert Membership.new(user: users(:dave), team: teams(:design)).valid?
  end

  test "a user can't be added to the same team twice" do
    membership = Membership.new(user: users(:alice), team: teams(:engineering))

    assert_not membership.valid?
    assert_includes membership.errors[:user_id], "is already a member of this team"
  end

  test "the unique index rejects a duplicate membership even when validation is skipped" do
    membership = Membership.new(user: users(:alice), team: teams(:engineering))

    assert_raises(ActiveRecord::RecordNotUnique) { membership.save!(validate: false) }
  end
end
