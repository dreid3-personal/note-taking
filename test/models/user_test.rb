require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires a name and an email" do
    user = User.new(name: " ", email: "")

    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
    assert_includes user.errors[:email], "can't be blank"
  end

  test "trims the name, and trims and lowercases the email" do
    user = User.create!(name: "  Erin  ", email: "  ERIN@Example.COM ")

    assert_equal "Erin", user.name
    assert_equal "erin@example.com", user.email
  end

  test "rejects a duplicate email, ignoring case and spaces" do
    [ "alice@example.com", "ALICE@example.com", "  Alice@Example.com  " ].each do |email|
      user = User.new(name: "Another Alice", email: email)

      assert_not user.valid?, "#{email.inspect} should be rejected"
      assert_includes user.errors[:email], "has already been taken"
    end
  end

  test "the unique index rejects a duplicate email even when validation is skipped" do
    user = User.new(name: "Another Alice", email: "ALICE@example.com")

    assert_raises(ActiveRecord::RecordNotUnique) { user.save!(validate: false) }
  end

  test "the unique index ignores case even if normalization is bypassed" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      User.insert_all!([ { name: "Shouty Alice", email: "ALICE@EXAMPLE.COM" } ])
    end
  end

  test "a name can be up to 100 characters" do
    assert User.new(name: "a" * 100, email: "long@example.com").valid?

    user = User.new(name: "a" * 101, email: "long@example.com")
    assert_not user.valid?
    assert_includes user.errors[:name], "is too long (maximum is 100 characters)"
  end

  test "an email can be up to 254 characters" do
    domain = "@example.com"
    assert User.new(name: "Long", email: "a" * (254 - domain.length) + domain).valid?

    user = User.new(name: "Long", email: "a" * (255 - domain.length) + domain)
    assert_not user.valid?
    assert_includes user.errors[:email], "is too long (maximum is 254 characters)"
  end
end
