require "test_helper"

# Fixtures: see access_resolver_test.rb.
class BreadcrumbsTest < ActiveSupport::TestCase
  def breadcrumbs(item, user)
    Breadcrumbs.new(item, user: user, resolver: AccessResolver.new(user))
  end

  test "a folder's trail ends with the folder, a note's with its folder" do
    crumbs = breadcrumbs(folders(:alice_subfolder), users(:alice))
    assert_equal :my_notes, crumbs.section
    assert_equal [ folders(:alice_folder), folders(:alice_subfolder) ], crumbs.folders

    crumbs = breadcrumbs(notes(:alice_nested), users(:alice))
    assert_equal [ folders(:alice_folder) ], crumbs.folders
  end

  test "a top-level note has no folders" do
    crumbs = breadcrumbs(notes(:alice_private), users(:alice))

    assert_equal :my_notes, crumbs.section
    assert_empty crumbs.folders
  end

  test "items reached through a shared folder start at Shared with me" do
    crumbs = breadcrumbs(notes(:alice_nested), users(:carol))

    assert_equal :shared_with_me, crumbs.section
    assert_equal [ folders(:alice_folder) ], crumbs.folders
  end

  test "items in a team folder start at Team folders" do
    crumbs = breadcrumbs(notes(:eng_plan), users(:bob))

    assert_equal :team_folders, crumbs.section
    assert_equal [ folders(:engineering) ], crumbs.folders
  end

  test "the trail starts below the folders the user can't open" do
    folders(:alice_folder).shares.destroy_all
    Share.create!(folder: folders(:alice_subfolder), user: users(:carol), access: :view)

    crumbs = breadcrumbs(folders(:alice_subfolder), users(:carol))

    assert_equal :shared_with_me, crumbs.section
    assert_equal [ folders(:alice_subfolder) ], crumbs.folders
  end

  test "an author's note in a team folder they left is under My notes" do
    note = Note.create!(title: "Bob eng note", author: users(:bob), folder: folders(:engineering))
    memberships(:bob_engineering).destroy

    crumbs = breadcrumbs(note, users(:bob))

    assert_equal :my_notes, crumbs.section
    assert_empty crumbs.folders
  end
end
