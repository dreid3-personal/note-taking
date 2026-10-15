require "test_helper"

class AccessLevelTest < ActiveSupport::TestCase
  test "orders none < view < edit" do
    assert_operator AccessLevel::NONE, :<, AccessLevel::VIEW
    assert_operator AccessLevel::VIEW, :<, AccessLevel::EDIT
    assert_equal [ AccessLevel::NONE, AccessLevel::VIEW, AccessLevel::EDIT ],
      [ AccessLevel::EDIT, AccessLevel::NONE, AccessLevel::VIEW ].sort
  end

  test "looks up levels by name and passes levels through" do
    assert_same AccessLevel::VIEW, AccessLevel["view"]
    assert_same AccessLevel::EDIT, AccessLevel[:edit]
    assert_same AccessLevel::NONE, AccessLevel[AccessLevel::NONE]
    assert_raises(ArgumentError) { AccessLevel["admin"] }
  end

  test "can't be built from an arbitrary name" do
    assert_raises(NoMethodError) { AccessLevel.new("admin") }
  end

  test "picks the highest of several levels" do
    assert_equal AccessLevel::EDIT, AccessLevel.highest([ "view", :edit, AccessLevel::NONE ])
    assert_equal AccessLevel::VIEW, AccessLevel.highest([ "none", "view" ])
    assert_equal AccessLevel::NONE, AccessLevel.highest([ "none" ])
  end

  test "the highest of an empty list is none" do
    assert_equal AccessLevel::NONE, AccessLevel.highest([])
  end

  test "edit allows viewing and editing" do
    assert AccessLevel::EDIT.view?
    assert AccessLevel::EDIT.edit?
    assert_not AccessLevel::EDIT.none?
  end

  test "view allows only viewing" do
    assert AccessLevel::VIEW.view?
    assert_not AccessLevel::VIEW.edit?
    assert_not AccessLevel::VIEW.none?
  end

  test "none allows neither" do
    assert_not AccessLevel::NONE.view?
    assert_not AccessLevel::NONE.edit?
    assert AccessLevel::NONE.none?
  end

  test "compares with level names" do
    assert_equal AccessLevel::VIEW, "view"
    assert_operator AccessLevel::EDIT, :>, :view
    assert_not_equal AccessLevel::NONE, nil
    assert_not_equal AccessLevel::VIEW, "owner"
    assert_nil AccessLevel::VIEW <=> "owner"
    assert_nil AccessLevel::VIEW <=> 1
  end

  test "converts to its name" do
    assert_equal "edit", AccessLevel::EDIT.to_s
    assert_equal :view, AccessLevel::VIEW.to_sym
  end
end
