class CreateShares < ActiveRecord::Migration[8.1]
  def change
    create_table :shares do |t|
      # Each composite unique index below starts with folder_id or note_id, so they need no index of their own.
      t.references :folder, foreign_key: true, index: false
      t.references :note, foreign_key: true, index: false
      t.references :user, foreign_key: true
      t.references :team, foreign_key: true
      t.string :access, null: false

      t.timestamps

      t.check_constraint "access IN ('view', 'edit')", name: "shares_access_check"
      t.check_constraint "(folder_id IS NULL) <> (note_id IS NULL)", name: "shares_one_item_check"
      t.check_constraint "(user_id IS NULL) <> (team_id IS NULL)", name: "shares_one_grantee_check"
    end

    # SQLite treats NULLs as distinct, so e.g. a team share (user_id NULL) never collides on [note_id, user_id].
    add_index :shares, [ :note_id, :user_id ], unique: true
    add_index :shares, [ :note_id, :team_id ], unique: true
    add_index :shares, [ :folder_id, :user_id ], unique: true
    add_index :shares, [ :folder_id, :team_id ], unique: true
  end
end
