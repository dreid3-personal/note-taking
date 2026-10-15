require "test_helper"

# The Authorization concern on its own. The request tests cover how each route uses it.
class AuthorizationTest < ActiveSupport::TestCase
  def controller_for(user)
    ApplicationController.new.tap { |controller| controller.define_singleton_method(:current_user) { user } }
  end

  test "nothing is allowed without a current user" do
    controller = controller_for(nil)

    %i[view edit rename author].each do |action|
      assert_not controller.send(:allowed_to?, action, notes(:alice_private)), "#{action} was allowed"
    end
  end

  test "author actions are for the author, never on a team folder" do
    assert controller_for(users(:alice)).send(:allowed_to?, :author, folders(:alice_folder))
    assert_not controller_for(users(:alice)).send(:allowed_to?, :author, folders(:engineering))
    assert_not controller_for(users(:bob)).send(:allowed_to?, :author, notes(:eng_plan))
  end
end
