ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel processes where the OS can fork. Threaded workers would share the one
    # database connection that transactional fixtures pin, so Windows runs the tests in one process.
    parallelize(workers: Process.respond_to?(:fork) ? :number_of_processors : 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

module ActionDispatch
  class IntegrationTest
    # Picks the user in the sidebar's "You are" switcher.
    def switch_to(user)
      patch current_user_path, params: { user_id: user.id }
    end

    # The request was refused as if the item didn't exist.
    def assert_not_found
      assert_response :not_found
      assert_select "title", "The page you were looking for doesn't exist (404 Not found)"
    end

    # The request was refused with a redirect to the item and the permission message.
    def assert_not_allowed(item)
      assert_redirected_to item
      assert_response :see_other
      assert_equal "You don't have permission to do that.", flash[:alert]
    end

    # The text of every element matching the selector, in order.
    def assert_texts(selector, expected)
      assert_equal expected, css_select(selector).map { |element| element.text.strip }
    end

    # None of these buttons (links or button_to forms) is on the page.
    def assert_no_buttons(*labels)
      labels.each do |label|
        assert_select "main a, main button", { text: label, count: 0 }, "#{label} shouldn't be shown"
      end
    end

    # Calls the JSON API as the user (as: nil sends no X-User-Id), with params as a JSON body.
    def api(method, path, as: nil, params: nil, headers: {})
      headers = headers.merge("Content-Type" => "application/json")
      headers["X-User-Id"] = as.id.to_s if as
      send(method, path, params: params&.to_json, headers: headers)
    end

    def assert_api_unauthorized
      assert_response :unauthorized
      assert_match "X-User-Id", response.parsed_body["error"]
    end

    # Refused as if the item didn't exist: the same body as for a missing record.
    def assert_api_not_found
      assert_response :not_found
      assert_equal({ "error" => "Not found" }, response.parsed_body)
    end

    def assert_api_forbidden
      assert_response :forbidden
      assert_equal({ "error" => "You don't have permission to do that." }, response.parsed_body)
    end

    def assert_api_bad_request
      assert_response :bad_request
      assert_equal({ "error" => "Bad request" }, response.parsed_body)
    end

    # The visitor was sent to the Notes page to pick a user.
    def assert_asked_to_pick_user
      assert_redirected_to root_path
      assert_nil flash[:alert]
    end
  end
end
