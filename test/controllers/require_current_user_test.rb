require "test_helper"

class RequireCurrentUserTest < ActionDispatch::IntegrationTest
  class GuardedController < ApplicationController
    before_action :require_current_user

    def show
      render plain: "Hello, #{current_user.name}"
    end
  end

  test "redirects to the Notes page without a current user, and lets a current user through" do
    with_routing do |set|
      set.draw do
        root "notes#index"
        resource :current_user, only: :update
        resources :users, only: :index
        get "guarded", to: "require_current_user_test/guarded#show"
      end

      get "/guarded"
      assert_redirected_to root_path
      assert_response :see_other

      patch current_user_path, params: { user_id: users(:alice).id }
      get "/guarded"
      assert_response :success
      assert_equal "Hello, Alice", response.body
    end
  end
end
